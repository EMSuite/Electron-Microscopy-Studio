//
//  DictionaryIndexingMetal.swift
//  Role: the float32 GPU twin of `DictionaryIndexing.matchCPU`: the score matrix experimental · dictionaryᵀ of prepared (centred,
//        unit-norm) patterns, the product kikuchipy computes with `da.einsum("ik,mk->im", ..., dtype=float32)`, as one
//        `MPSMatrixMultiplication` per dictionary chunk (#624; a hand-written tiled kernel before). The experimental patterns go to the
//        GPU once per indexing run, prepared straight into their buffer; the dictionary and score buffers are made once per run, two
//        of each, so one chunk's product runs while the CPU prepares the next chunk and merges the one before. Same port and licence
//        as DictionaryIndexing.swift.
//        Checked against the float64 CPU path in EMStudioTests/SEMDictionaryIndexingParityTests.swift within `tolerance`.
//

import Foundation
import Metal
import MetalPerformanceShaders
import TEMBase

package nonisolated enum DictionaryIndexingMetal {
    /// The bound on |GPU − CPU| of a score (both in -1 ... 1): the float32 rounding of two unit vectors of a few thousand values and
    /// of their product's running sum stays near 1e-6; 1e-5 leaves room for another GPU's summation.
    package static let tolerance = 1e-5

    /// Work (experimental × dictionary × pixels) from which the GPU pays on the automatic backend: a 3 x 3 scan against ten
    /// thousand 60 x 60 patterns (3e8) stays on the CPU, a whole scan (1e11) goes to the GPU.
    package static let workThreshold = 1_000_000_000

    /// Whether this Mac has a Metal device that Metal Performance Shaders supports.
    package static var isAvailable: Bool { (try? pipeline.get()) != nil }

    package enum Error: Swift.Error, LocalizedError, Equatable {
        case noMetalDevice
        case tooLarge(Int)
        case metal(String)

        package var errorDescription: String? {
            switch self {
            case .noMetalDevice: return "This Mac has no Metal device for GPU dictionary indexing."
            case .tooLarge(let n): return "\(n) bytes are more than one GPU buffer can hold."
            case .metal(let text): return "GPU dictionary indexing failed: \(text)"
            }
        }
    }

    private struct Pipeline: @unchecked Sendable {
        let device: MTLDevice
        let queue: MTLCommandQueue
    }

    private static let pipeline: Result<Pipeline, Error> = {
        guard let device = MTLCreateSystemDefaultDevice(), MPSSupportsMTLDevice(device) else { return .failure(.noMetalDevice) }
        guard let queue = device.makeCommandQueue() else { return .failure(.metal("no command queue")) }
        return .success(Pipeline(device: device, queue: queue))
    }()

    /// The bytes of `values` float32 values, refused when one buffer cannot hold them.
    private static func bytes(_ values: Int, device: MTLDevice) throws -> Int {
        let (bytes, overflow) = max(values, 1).multipliedReportingOverflow(by: MemoryLayout<Float>.stride)
        guard !overflow, bytes <= device.maxBufferLength else { throw Error.tooLarge(overflow ? Int.max : bytes) }
        return bytes
    }

    /// One indexing run on the GPU: the experimental patterns in their buffer, and two dictionary chunk and score buffers of `capacity`
    /// patterns each. `submit` starts a chunk's product; a chunk's scores are handed to `completed` once its product is done, at the
    /// latest by the next `submit` that needs its buffers or by `finish`, in submission order.
    nonisolated final class Matcher {
        private let p: Pipeline
        private let experimental: MTLBuffer
        private let count: Int
        private let length: Int
        private let capacity: Int
        private let dictionaries: [MTLBuffer]
        private let scores: [MTLBuffer]
        /// The chunks in flight, oldest first: the slot they use, their size and their first dictionary index.
        private var inFlight: [(commands: MTLCommandBuffer, slot: Int, size: Int, offset: Int)] = []
        private var nextSlot = 0

        /// `count` experimental patterns of `length` prepared values each, written by `fill` straight into the GPU's float32 buffer
        /// (row-major), and room for dictionary chunks of up to `capacity` patterns.
        init(count: Int, length: Int, capacity: Int, fill: (UnsafeMutablePointer<Float>) -> Void) throws {
            let pipeline = try DictionaryIndexingMetal.pipeline.get()
            p = pipeline
            let (eValues, e) = count.multipliedReportingOverflow(by: length)
            let (dValues, d) = capacity.multipliedReportingOverflow(by: length)
            let (sValues, s) = count.multipliedReportingOverflow(by: capacity)
            guard !e, !d, !s else { throw Error.metal("\(count) patterns against chunks of \(capacity) are more than one buffer can address") }
            let eBytes = try DictionaryIndexingMetal.bytes(eValues, device: pipeline.device)
            let dBytes = try DictionaryIndexingMetal.bytes(dValues, device: pipeline.device)
            let sBytes = try DictionaryIndexingMetal.bytes(sValues, device: pipeline.device)
            guard let eBuffer = pipeline.device.makeBuffer(length: eBytes, options: .storageModeShared) else {
                throw Error.metal("could not allocate \(eBytes) bytes on the GPU")
            }
            var dBuffers: [MTLBuffer] = [], sBuffers: [MTLBuffer] = []
            for _ in 0 ..< 2 {
                guard let dBuffer = pipeline.device.makeBuffer(length: dBytes, options: .storageModeShared),
                      let sBuffer = pipeline.device.makeBuffer(length: sBytes, options: .storageModeShared) else {
                    throw Error.metal("could not allocate \(dBytes + sBytes) bytes on the GPU")
                }
                dBuffers.append(dBuffer); sBuffers.append(sBuffer)
            }
            fill(eBuffer.contents().assumingMemoryBound(to: Float.self))
            experimental = eBuffer
            dictionaries = dBuffers
            scores = sBuffers
            self.count = count
            self.length = length
            self.capacity = capacity
        }

        /// Starts the product of a chunk of `size` dictionary patterns (dictionary indices from `offset`) that `fill` prepares
        /// straight into the GPU's float32 buffer (row-major), after handing the scores of the chunk whose buffers it takes to
        /// `completed` (experimental × size, row-major, its size, its offset).
        func submit(size: Int, offset: Int, completed: (UnsafePointer<Float>, Int, Int) -> Void,
                    fill: (UnsafeMutablePointer<Float>) -> Void) throws {
            guard size >= 1, size <= capacity else { throw Error.metal("a chunk of \(size) patterns does not fit the \(capacity) the buffers hold") }
            let slot = nextSlot
            nextSlot = (nextSlot + 1) % dictionaries.count
            if let i = inFlight.firstIndex(where: { $0.slot == slot }) {
                // Chunks complete in submission order, so the one in this slot is the oldest: nothing older is left waiting.
                try complete(upTo: i, completed)
            }
            fill(dictionaries[slot].contents().assumingMemoryBound(to: Float.self))
            guard let commands = p.queue.makeCommandBuffer() else { throw Error.metal("no command buffer") }
            let float = MemoryLayout<Float>.stride
            let left = MPSMatrix(buffer: experimental, descriptor: MPSMatrixDescriptor(rows: count, columns: length, rowBytes: length * float,
                                                                                       dataType: .float32))
            let right = MPSMatrix(buffer: dictionaries[slot], descriptor: MPSMatrixDescriptor(rows: size, columns: length,
                                                                                               rowBytes: length * float, dataType: .float32))
            let result = MPSMatrix(buffer: scores[slot], descriptor: MPSMatrixDescriptor(rows: count, columns: size, rowBytes: size * float,
                                                                                         dataType: .float32))
            let product = MPSMatrixMultiplication(device: p.device, transposeLeft: false, transposeRight: true, resultRows: count,
                                                  resultColumns: size, interiorColumns: length, alpha: 1, beta: 0)
            product.encode(commandBuffer: commands, leftMatrix: left, rightMatrix: right, resultMatrix: result)
            commands.commit()
            inFlight.append((commands, slot, size, offset))
        }

        /// Waits for every chunk still in flight and hands its scores to `completed`, oldest first.
        func finish(completed: (UnsafePointer<Float>, Int, Int) -> Void) throws {
            if !inFlight.isEmpty { try complete(upTo: inFlight.count - 1, completed) }
        }

        /// Waits for the chunks in flight up to index `last` (oldest first) and hands each one's scores on.
        private func complete(upTo last: Int, _ completed: (UnsafePointer<Float>, Int, Int) -> Void) throws {
            let done = inFlight[0 ... last]
            inFlight.removeFirst(last + 1)
            for chunk in done {
                chunk.commands.waitUntilCompleted()
                if let error = chunk.commands.error { throw Error.metal(error.localizedDescription) }
                completed(UnsafePointer(scores[chunk.slot].contents().assumingMemoryBound(to: Float.self)), chunk.size, chunk.offset)
            }
        }
    }
}
