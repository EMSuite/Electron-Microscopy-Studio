//
//  StoredPatterns.swift
//  Role: a block of EBSD patterns held at the type they are indexed in (#620; the suite's memory rule: data at its native bit
//        depth, Float32 only while a computation runs): the file's type when no processing stage is on (uint8 or uint16, one or
//        two bytes a pixel), the pipeline's float32 when one is. Dictionary indexing and refinement read a block of scan rows into
//        one of these and widen one pattern at a time to the type their arithmetic runs in (`gather`): float64 for the dictionary's
//        CPU reference, float32 for the refinement's NCC. Each value is the one `FormatoArray.doubles()` gives, then rounded once
//        to Float where a Float is asked for, so the numbers are those of the Double blocks these replace.
//

import Foundation
import FormatoCore
import TEMBase

/// `count` patterns of `pixels` values each, row-major one after the other, little-endian at `dataType` (C order, as
/// `FormatoArray` holds them).
package nonisolated struct StoredPatterns: Sendable, Equatable {
    package enum Error: Swift.Error, Equatable, LocalizedError {
        case notScalar(FormatoDataType)
        case byteCount(expected: Int, got: Int)
        case mixedTypes(FormatoDataType, FormatoDataType)

        package var errorDescription: String? {
            switch self {
            case .notScalar(let t): "Patterns stored as \(t.rawValue) colour values cannot be indexed."
            case .byteCount(let e, let g): "The patterns take \(g) bytes where \(e) were expected."
            case .mixedTypes(let a, let b): "The patterns are read as \(a.rawValue) and \(b.rawValue)."
            }
        }
    }

    package let dataType: FormatoDataType
    package let count: Int
    package let pixels: Int
    package let bytes: Data

    package init(dataType: FormatoDataType, count: Int, pixels: Int, bytes: Data) throws {
        guard dataType.components == 1 else { throw Error.notScalar(dataType) }
        let (perPattern, a) = pixels.multipliedReportingOverflow(by: dataType.byteSize)
        let (need, b) = count.multipliedReportingOverflow(by: perPattern)
        guard count >= 0, pixels >= 0, !a, !b, bytes.count == need else {
            throw Error.byteCount(expected: a || b ? -1 : need, got: bytes.count)
        }
        self.dataType = dataType; self.count = count; self.pixels = pixels; self.bytes = bytes
    }

    /// Float64 values (a parity reference, a test): `values.count / pixels` patterns; a remainder is refused.
    package init(doubles values: [Double], pixels: Int) throws {
        let count = pixels > 0 ? values.count / pixels : 0
        try self.init(dataType: .float64, count: count, pixels: pixels, bytes: values.withUnsafeBufferPointer { Data(buffer: $0) })
    }

    /// Float32 values (a parity reference, a test): `values.count / pixels` patterns; a remainder is refused.
    package init(floats values: [Float], pixels: Int) throws {
        let count = pixels > 0 ? values.count / pixels : 0
        try self.init(dataType: .float32, count: count, pixels: pixels, bytes: values.withUnsafeBufferPointer { Data(buffer: $0) })
    }

    /// One block of rows put together from its rows, in order, each read at the same type.
    package init(joining parts: [StoredPatterns], pixels: Int, emptyType: FormatoDataType) throws {
        guard let type = parts.first?.dataType else {
            try self.init(dataType: emptyType, count: 0, pixels: pixels, bytes: Data())
            return
        }
        var bytes = Data()
        bytes.reserveCapacity(parts.reduce(0) { $0 + $1.bytes.count })
        var count = 0
        for part in parts {
            guard part.dataType == type else { throw Error.mixedTypes(type, part.dataType) }
            guard part.pixels == pixels else { throw Error.byteCount(expected: part.count * pixels * type.byteSize, got: part.bytes.count) }
            bytes.append(part.bytes)
            count += part.count
        }
        try self.init(dataType: type, count: count, pixels: pixels, bytes: bytes)
    }

    /// The bytes the patterns take in memory.
    package var byteCount: Int { bytes.count }

    /// Pattern `p`'s values at `kept` (every pixel when nil), widened to `T` through Double, written to `dst` (room for `kept.count`
    /// or `pixels` values).
    package func gather<T: BinaryFloatingPoint>(pattern p: Int, kept: [Int]?, into dst: UnsafeMutablePointer<T>) {
        let start = p * pixels
        let n = kept?.count ?? pixels
        bytes.withUnsafeBytes { raw in
            func run<S: BitwiseCopyable>(_: S.Type, _ convert: (S) -> Double) {
                let size = MemoryLayout<S>.size
                if let kept {
                    for k in 0 ..< n { dst[k] = T(convert(raw.loadUnaligned(fromByteOffset: (start + kept[k]) * size, as: S.self))) }
                } else {
                    for k in 0 ..< n { dst[k] = T(convert(raw.loadUnaligned(fromByteOffset: (start + k) * size, as: S.self))) }
                }
            }
            switch dataType {
            case .uint8: run(UInt8.self) { Double($0) }
            case .int8: run(Int8.self) { Double($0) }
            case .uint16: run(UInt16.self) { Double(UInt16(littleEndian: $0)) }
            case .int16: run(Int16.self) { Double(Int16(littleEndian: $0)) }
            case .uint32: run(UInt32.self) { Double(UInt32(littleEndian: $0)) }
            case .int32: run(Int32.self) { Double(Int32(littleEndian: $0)) }
            case .uint64: run(UInt64.self) { Double(UInt64(littleEndian: $0)) }
            case .int64: run(Int64.self) { Double(Int64(littleEndian: $0)) }
            case .float32: run(UInt32.self) { Double(Float(bitPattern: UInt32(littleEndian: $0))) }
            case .float64: run(UInt64.self) { Double(bitPattern: UInt64(littleEndian: $0)) }
            case .rgb8, .rgba8, .rgb16, .rgba16: break   // refused by init
            }
        }
    }

    /// Pattern `p`'s values at `kept` (all when nil) as Floats.
    package func floats(pattern p: Int, kept: [Int]?) -> [Float] {
        let n = kept?.count ?? pixels
        return [Float](unsafeUninitializedCapacity: n) { out, initialized in
            if let base = out.baseAddress { gather(pattern: p, kept: kept, into: base) }
            initialized = n
        }
    }

    /// Every value as a Double, pattern after pattern (a test's view).
    package func doubles() -> [Double] {
        let n = count * pixels
        return [Double](unsafeUninitializedCapacity: n) { out, initialized in
            if let base = out.baseAddress { for p in 0 ..< count { gather(pattern: p, kept: nil, into: base + p * pixels) } }
            initialized = n
        }
    }
}
