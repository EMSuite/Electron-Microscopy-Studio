//
//  MasterPatternProjectionMetal.swift
//  Role: the float32 GPU twin of `MasterPatternProjection.project` for many patterns at once (a dictionary): one thread per pattern
//        pixel turns the pixel's direction cosine by the pattern's quaternion, maps it to the square Lambert projection and
//        interpolates the master pattern bilinearly, exactly the steps of the CPU path in float32 with precise (not fast) math; each
//        pattern is then rescaled to -1 ... 1 on the CPU unless the master pattern is float32 already (the CPU path's rule,
//        `get_patterns`' `rescale = dtype_out != self.data.dtype`; EMsoft writes float32). The kernel is compiled from the source below at first use (no .metal
//        file: the app target's shader library stays the shell's). Same ports and licences as MasterPatternProjection.swift.
//        A dictionary projected chunk by chunk goes through one `Projector`: the master pattern and the cosines uploaded once, the
//        buffers made once, and a size the kernel's 32-bit indices cannot address refused as `tooLarge` (#624).
//        Checked against the float64 CPU path in EMStudioTests/MasterPatternParityTests.swift within `tolerance` (decision in
//        docs/decisions.md: float32 Lambert coordinates on a 401 px master pattern move an interpolation weight by ~1e-5).
//

import FormatoEBSD
import Foundation
import FormatoCore
import Metal

package nonisolated enum MasterPatternProjectionMetal {
    /// The bound on |GPU − CPU| of a pattern rescaled to -1 ... 1: 1e-3, thirty times the 3.2e-5 a float32 emulation of the
    /// kernel measured on the Ni 20 kV pattern over 403 orientations (2026-11-06); the GPU's own transcendentals sit inside it.
    package static let tolerance = 1e-3

    /// Whether this Mac has a Metal device.
    package static var isAvailable: Bool { MTLCreateSystemDefaultDevice() != nil }

    private struct Pipeline: @unchecked Sendable {
        let device: MTLDevice
        let queue: MTLCommandQueue
        let state: MTLComputePipelineState
    }

    /// Built once: the device, a queue and the compiled kernel (or why not).
    private static let pipeline: Result<Pipeline, MasterPatternProjection.Error> = {
        guard let device = MTLCreateSystemDefaultDevice() else { return .failure(.noMetalDevice) }
        guard let queue = device.makeCommandQueue() else { return .failure(.metal("no command queue")) }
        do {
            let options = MTLCompileOptions()
            options.mathMode = .safe
            let library = try device.makeLibrary(source: kernelSource, options: options)
            guard let function = library.makeFunction(name: "project_master_pattern") else { return .failure(.metal("no kernel function")) }
            let state = try device.makeComputePipelineState(function: function)
            return .success(Pipeline(device: device, queue: queue, state: state))
        } catch {
            return .failure(.metal(error.localizedDescription))
        }
    }()

    /// The patterns as float32, `rotations.count` × rows × columns, row-major: rescaled to -1 ... 1 per pattern, or as stored when the
    /// master pattern is float32 (as `MasterPatternProjection.project` with float32 output).
    package static func project(master: EBSDMasterPattern, rotations: [SIMD4<Double>], detector: EBSDDetectorGeometry,
                                energy: Double? = nil) throws -> [Float] {
        try MasterPatternProjection.checkSuitable(master)
        let centres = detector.projectionCenters.count
        guard centres == 1 || centres == rotations.count else {
            throw MasterPatternProjection.Error.centreCount(centres: centres, rotations: rotations.count)
        }
        guard detector.rows * detector.columns > 0 else { throw MasterPatternProjection.Error.emptyDetector }
        if rotations.isEmpty { return [] }
        let projector = try Projector(master: master, detector: detector, energy: energy, capacity: rotations.count)
        return try projector.withPatterns(rotations[...]) { Array($0) }
    }

    /// The GPU side of projecting a dictionary chunk by chunk: the kernel's inputs that do not change between chunks (the master
    /// pattern's two hemispheres, the detector's direction cosines) uploaded once, and the rotation and output buffers made once for
    /// chunks of up to `capacity` patterns (#624: each chunk uploaded the master pattern again and allocated its buffers).
    package nonisolated final class Projector {
        private let p: Pipeline
        private let upper: MTLBuffer
        private let lower: MTLBuffer
        private let cosines: MTLBuffer
        private let quaternions: MTLBuffer
        private let output: MTLBuffer
        private let pixels: Int
        private let centres: Int
        private let capacity: Int
        private let side: Int
        private let rescales: Bool

        /// Refuses a master pattern that cannot be projected, an empty detector, and a size the kernel's 32-bit indices cannot
        /// address (`MasterPatternProjection.Error.tooLarge`): the output index pattern × pixels + pixel, the cosines' centre × pixels
        /// + pixel (unsigned), and the master pattern's side² (signed `int` in the kernel).
        package init(master: EBSDMasterPattern, detector: EBSDDetectorGeometry, energy: Double? = nil, capacity: Int) throws {
            try MasterPatternProjection.checkSuitable(master)
            let pixels = detector.rows * detector.columns
            guard pixels > 0 else { throw MasterPatternProjection.Error.emptyDetector }
            let capacity = max(capacity, 1)
            let centres = detector.projectionCenters.count
            let limit = Int(UInt32.max)
            let (outValues, a) = capacity.multipliedReportingOverflow(by: pixels)
            let (cosineValues, b) = max(centres, 1).multipliedReportingOverflow(by: pixels)
            let (masterValues, c) = master.side.multipliedReportingOverflow(by: master.side)
            guard !a, outValues <= limit else { throw MasterPatternProjection.Error.tooLarge(a ? Int.max : outValues) }
            guard !b, cosineValues <= limit else { throw MasterPatternProjection.Error.tooLarge(b ? Int.max : cosineValues) }
            guard !c, masterValues <= Int(Int32.max) else { throw MasterPatternProjection.Error.tooLarge(c ? Int.max : masterValues) }
            let p = try MasterPatternProjectionMetal.pipeline.get()
            let (upperValues, lowerValues) = try master.hemispheres(energy: energy)
            // Direction cosines in float64 on the CPU (one set per centre, as the reference), handed to the GPU as float4.
            let cosineSets = MasterPatternProjection.directionCosines(detector: detector).flatMap { set in
                set.map { SIMD4<Float>(Float($0.x), Float($0.y), Float($0.z), 0) }
            }
            let outputBytes = outValues * MemoryLayout<Float>.stride
            let quaternionBytes = capacity * MemoryLayout<SIMD4<Float>>.stride
            guard outputBytes <= p.device.maxBufferLength else { throw MasterPatternProjection.Error.tooLarge(outputBytes) }
            guard let upBuffer = upperValues.withUnsafeBytes({ b in b.baseAddress.flatMap { p.device.makeBuffer(bytes: $0, length: b.count, options: .storageModeShared) } }),
                  let loBuffer = lowerValues.withUnsafeBytes({ b in b.baseAddress.flatMap { p.device.makeBuffer(bytes: $0, length: b.count, options: .storageModeShared) } }),
                  let dcBuffer = cosineSets.withUnsafeBytes({ b in b.baseAddress.flatMap { p.device.makeBuffer(bytes: $0, length: b.count, options: .storageModeShared) } }),
                  let qBuffer = p.device.makeBuffer(length: quaternionBytes, options: .storageModeShared),
                  let outBuffer = p.device.makeBuffer(length: outputBytes, options: .storageModeShared) else {
                throw MasterPatternProjection.Error.metal("could not allocate \(outputBytes) bytes on the GPU")
            }
            self.p = p
            upper = upBuffer; lower = loBuffer; cosines = dcBuffer; quaternions = qBuffer; output = outBuffer
            self.pixels = pixels; self.centres = centres; self.capacity = capacity; self.side = master.side
            // `_rescale_with_min_max` to -1 ... 1, per pattern, only when the master pattern is not float32 already (`get_patterns`:
            // `rescale = dtype_out != self.data.dtype`, as `MasterPatternProjection.project`).
            rescales = master.dataType != .float32
        }

        /// Projects `rotations` (at most `capacity`; with several projection centres, one per rotation) and hands `body` the patterns,
        /// float32, rotations × rows × columns, row-major, in this projector's output buffer: valid until `body` returns.
        package func withPatterns<R>(_ rotations: ArraySlice<SIMD4<Double>>, _ body: (UnsafeBufferPointer<Float>) throws -> R) throws -> R {
            let count = rotations.count
            guard centres == 1 || centres == count else {
                throw MasterPatternProjection.Error.centreCount(centres: centres, rotations: count)
            }
            guard count <= capacity else { throw MasterPatternProjection.Error.tooLarge(count * pixels) }
            if count == 0 { return try body(UnsafeBufferPointer(start: nil, count: 0)) }
            let q = quaternions.contents().assumingMemoryBound(to: SIMD4<Float>.self)
            for (n, r) in rotations.enumerated() { q[n] = SIMD4<Float>(Float(r.x), Float(r.y), Float(r.z), Float(r.w)) }
            var params = Params(pixels: UInt32(pixels), patterns: UInt32(count), side: UInt32(side),
                                varying: centres == 1 ? 0 : 1, scale: Float(Double(side - 1) / 2))
            guard let commands = p.queue.makeCommandBuffer(), let encoder = commands.makeComputeCommandEncoder() else {
                throw MasterPatternProjection.Error.metal("no command buffer")
            }
            encoder.setComputePipelineState(p.state)
            encoder.setBuffer(quaternions, offset: 0, index: 0)
            encoder.setBuffer(cosines, offset: 0, index: 1)
            encoder.setBuffer(upper, offset: 0, index: 2)
            encoder.setBuffer(lower, offset: 0, index: 3)
            encoder.setBuffer(output, offset: 0, index: 4)
            encoder.setBytes(&params, length: MemoryLayout<Params>.stride, index: 5)
            let width = min(p.state.threadExecutionWidth, pixels)
            let height = max(1, min(p.state.maxTotalThreadsPerThreadgroup / width, count))
            encoder.dispatchThreads(MTLSize(width: pixels, height: count, depth: 1),
                                    threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1))
            encoder.endEncoding()
            commands.commit()
            commands.waitUntilCompleted()
            if let error = commands.error { throw MasterPatternProjection.Error.metal(error.localizedDescription) }
            let out = output.contents().assumingMemoryBound(to: Float.self)
            if rescales { try Self.rescale(out, patterns: count, pixels: pixels) }
            return try body(UnsafeBufferPointer(start: out, count: count * pixels))
        }

        /// The output's pointer, shared by the rescaling workers: each pattern rescales its own rows.
        private struct Rows: @unchecked Sendable { let base: UnsafeMutablePointer<Float> }

        /// Each pattern to -1 ... 1 in place, over the cores (the same float32 arithmetic as the serial loop it replaces); the first
        /// flat pattern is refused (`flatPattern`), as the CPU path refuses it.
        private static func rescale(_ out: UnsafeMutablePointer<Float>, patterns: Int, pixels: Int) throws {
            let rows = Rows(base: out)
            var flat = [Bool](repeating: false, count: patterns)
            flat.withUnsafeMutableBufferPointer { f in
                guard let flags = f.baseAddress else { return }
                let marks = FlatMarks(base: flags)
                DispatchQueue.concurrentPerform(iterations: patterns) { n in
                    let row = rows.base + n * pixels
                    var lowest = row[0], highest = row[0]
                    for i in 1 ..< pixels {
                        lowest = min(lowest, row[i]); highest = max(highest, row[i])
                    }
                    guard highest > lowest else {
                        (marks.base + n).pointee = true
                        return
                    }
                    let span = highest - lowest
                    for i in 0 ..< pixels { row[i] = (row[i] - lowest) / span * 2 - 1 }
                }
            }
            if let n = flat.firstIndex(of: true) { throw MasterPatternProjection.Error.flatPattern(n) }
        }

        private struct FlatMarks: @unchecked Sendable { let base: UnsafeMutablePointer<Bool> }
    }

    /// The kernel's constants, laid out as the `Params` struct of the source.
    private struct Params {
        var pixels: UInt32
        var patterns: UInt32
        var side: UInt32
        var varying: UInt32
        var scale: Float
    }

    private static let kernelSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Params { uint pixels; uint patterns; uint side; uint varying; float scale; };

    static float sgn(float x) { return x > 0.0f ? 1.0f : (x < 0.0f ? -1.0f : 0.0f); }

    kernel void project_master_pattern(device const float4 *rotations [[buffer(0)]],
                                       device const float4 *cosines [[buffer(1)]],
                                       device const float *upper [[buffer(2)]],
                                       device const float *lower [[buffer(3)]],
                                       device float *out [[buffer(4)]],
                                       constant Params &p [[buffer(5)]],
                                       uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= p.pixels || gid.y >= p.patterns) { return; }
        float4 q = rotations[gid.y];
        float4 d = cosines[(p.varying != 0 ? gid.y * p.pixels : 0u) + gid.x];
        float a = q.x, b = q.y, c = q.z, e = q.w;
        float aa = a * a, bb = b * b, cc = c * c, ee = e * e;
        float ac = a * c, ab = a * b, ae = a * e, bc = b * c, be = b * e, ce = c * e;
        float vx = (aa + bb - cc - ee) * d.x + 2.0f * ((ac + be) * d.z + (bc - ae) * d.y);
        float vy = (aa - bb + cc - ee) * d.y + 2.0f * ((ae + bc) * d.x + (ce - ab) * d.z);
        float vz = (aa - bb - cc + ee) * d.z + 2.0f * ((ab + ce) * d.y + (be - ac) * d.x);
        float n = precise::sqrt(vx * vx + vy * vy + vz * vz);
        float x = vx / n, y = vy / n, z = vz / n;
        float az = fabs(z);
        // 1 - |z| as (x² + y²) / (1 + |z|): the same number for a unit vector, without float32's cancellation near the
        // pole (1 - |z| loses up to 3e-4 px of Lambert coordinate there, measured as 2e-3 on the -1 ... 1 scale on an M-series GPU).
        float sz = precise::sqrt(2.0f * (x * x + y * y) / (1.0f + az));
        const float sqrtPiOver2 = 0.886226925452758f;
        const float twoOverSqrtPi = 1.128379167095513f;
        const float sqrtPiHalf = 1.253314137315500f;
        float lx = 0.0f, ly = 0.0f;
        if (az != 1.0f) {
            if (fabs(y) <= fabs(x)) {
                float s = sgn(x);
                lx = s * sz * sqrtPiOver2;
                ly = s * sz * twoOverSqrtPi * precise::atan(y / x);
            } else {
                float s = sgn(y);
                lx = s * sz * twoOverSqrtPi * precise::atan(x / y);
                ly = s * sz * sqrtPiOver2;
            }
        }
        float scale = p.scale;
        float i = scale * ly / sqrtPiHalf;
        float j = scale * lx / sqrtPiHalf;
        int side = int(p.side);
        int nii = int(i + scale), nij = int(j + scale);
        int niip = nii + 1, nijp = nij + 1;
        if (niip >= side) { niip = nii; }
        if (nijp >= side) { nijp = nij; }
        if (nii < 0) { nii = niip; }
        if (nij < 0) { nij = nijp; }
        float di = i - float(nii) + scale, dj = j - float(nij) + scale;
        float dim = 1.0f - di, djm = 1.0f - dj;
        device const float *mp = vz >= 0.0f ? upper : lower;
        out[gid.y * p.pixels + gid.x] = mp[nii * side + nij] * dim * djm + mp[niip * side + nij] * di * djm
            + mp[nii * side + nijp] * dim * dj + mp[niip * side + nijp] * di * dj;
    }
    """
}
