//
//  MasterPatternValues.swift
//  Role: a master pattern's intensities held at the type its file stores (#620; the suite's memory rule: data at its native bit
//        depth, Float32 only while a computation runs). EMsoft writes uint8 or float32 master patterns; a uint8 file of 11 energies
//        and two 1001 x 1001 hemispheres holds 22 MB here, where widened to Float it took 88 MB. A projection takes one energy's two
//        hemispheres as Float (`floats(_:)`), the block of work it computes on.
//        Every value reads as the Float it read as before: uint8 and uint16 are exact in Float, float32 is its bits, and a float64
//        file (which EMsoft does not write) is rounded to Float once, as the reader always did.
//

import Foundation
import TEMBase

/// A master pattern's intensities in C order (hemisphere, energy, row, column), at their stored type, read as Floats.
package nonisolated struct MasterPatternValues: Sendable, Equatable, RandomAccessCollection {
    /// The values as held: one array of the stored element type.
    package enum Storage: Sendable, Equatable {
        case uint8([UInt8])
        case uint16([UInt16])
        case float32([Float])
    }

    package let storage: Storage

    package init(_ storage: Storage) { self.storage = storage }

    /// Float values (a simulated master pattern, a float32 or float64 file).
    package init(_ floats: [Float]) { storage = .float32(floats) }

    package var startIndex: Int { 0 }

    package var endIndex: Int {
        switch storage {
        case .uint8(let a): a.count
        case .uint16(let a): a.count
        case .float32(let a): a.count
        }
    }

    package subscript(position: Int) -> Float {
        switch storage {
        case .uint8(let a): Float(a[position])
        case .uint16(let a): Float(a[position])
        case .float32(let a): a[position]
        }
    }

    /// The bytes the values take in memory.
    package var byteCount: Int {
        switch storage {
        case .uint8(let a): a.count
        case .uint16(let a): a.count * MemoryLayout<UInt16>.stride
        case .float32(let a): a.count * MemoryLayout<Float>.stride
        }
    }

    /// The values in `range` as Floats: the block a projection or a refinement computes on (one hemisphere of one energy).
    package func floats(_ range: Range<Int>) -> [Float] {
        switch storage {
        case .uint8(let a): a[range].map { Float($0) }
        case .uint16(let a): a[range].map { Float($0) }
        case .float32(let a): Array(a[range])
        }
    }

    /// The parts one after the other, of one stored type (the hemispheres of a file, upper first); nil when their types differ.
    package static func joined(_ parts: [MasterPatternValues]) -> MasterPatternValues? {
        guard let first = parts.first else { return MasterPatternValues([Float]()) }
        let total = parts.reduce(0) { $0 + $1.count }
        switch first.storage {
        case .uint8:
            var out: [UInt8] = []
            out.reserveCapacity(total)
            for part in parts {
                guard case .uint8(let a) = part.storage else { return nil }
                out += a
            }
            return MasterPatternValues(.uint8(out))
        case .uint16:
            var out: [UInt16] = []
            out.reserveCapacity(total)
            for part in parts {
                guard case .uint16(let a) = part.storage else { return nil }
                out += a
            }
            return MasterPatternValues(.uint16(out))
        case .float32:
            var out: [Float] = []
            out.reserveCapacity(total)
            for part in parts {
                guard case .float32(let a) = part.storage else { return nil }
                out += a
            }
            return MasterPatternValues(.float32(out))
        }
    }
}
