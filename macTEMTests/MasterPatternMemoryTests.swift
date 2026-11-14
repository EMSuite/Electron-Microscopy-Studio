//
//  MasterPatternMemoryTests.swift
//  #620: a master pattern stays at the type its file stores, and a projection or a refinement takes Floats of one energy only.
//  - The shipped Ni master pattern (uint8, 401 x 401, both hemispheres) holds one byte a value, its hemispheres reading as the
//    stored values.
//  - A master pattern of EMsoft's usual size (npx 500: 1001 x 1001, 10 to 20 keV in 1 keV bins, both hemispheres) holds 22 MB as
//    uint8, where widened to Float it took 88 MB; the energy a projection picks comes back as Floats of that energy alone, and the
//    refinement's master takes 8 MB.
//  Red on main: `EBSDMasterPattern.values` was `[Float]`, four bytes a uint8 value.
//

import Foundation
import FormatoCore
import TEMCore
import TEMSession
import XCTest

nonisolated final class MasterPatternMemoryTests: XCTestCase {
    func testTheNickelMasterPatternHoldsOneByteAValue() throws {
        let url = try XCTUnwrap(DemoDocuments.Shipped.nickelMasterPattern.url)
        let mp = try EMsoftMasterPatternReader.read(url: url, type: .ebsd, projection: .lambert, hemisphere: .both)
        let side = DemoDocuments.Shipped.nickelMasterPatternSide
        guard case .uint8 = mp.values.storage else { return XCTFail("held as \(mp.values.storage)") }
        XCTAssertEqual(mp.values.byteCount, 2 * side * side)
        let (upper, lower) = try mp.hemispheres(energy: nil)
        XCTAssertEqual(upper, Array(mp.values[0 ..< side * side]))
        XCTAssertEqual(lower, Array(mp.values[side * side ..< 2 * side * side]))
        XCTAssertEqual(upper.reduce(UInt64(0)) { $0 + UInt64($1) }, DemoDocuments.Shipped.nickelMasterPatternLambertSum)
    }

    func testARealSizeMasterPatternHoldsItsStoredBytesAndHandsOutOneEnergy() throws {
        let url = try XCTUnwrap(DemoDocuments.Shipped.nickelMasterPattern.url)
        var mp = try EMsoftMasterPatternReader.read(url: url, type: .ebsd, projection: .lambert, hemisphere: .both)
        let side = 1001, energies = Array(10 ... 20).map(Double.init), n = side * side
        // Each pattern one level: 10 x hemisphere + energy index, so a wrong pick shows in the value.
        var bytes = [UInt8](repeating: 0, count: 2 * energies.count * n)
        for h in 0 ..< 2 {
            for e in energies.indices { bytes.withUnsafeMutableBufferPointer { b in for p in 0 ..< n { b[(h * energies.count + e) * n + p] = UInt8(100 * h + e) } } }
        }
        mp.values = MasterPatternValues(.uint8(bytes))
        bytes = []
        mp.side = side
        mp.energies = energies
        mp.energyAxis.offset = 10; mp.energyAxis.scale = 1; mp.energyAxis.size = energies.count
        XCTAssertEqual(mp.values.byteCount, 22_044_022, "22 MB as uint8 (88 MB as Float)")

        let (upper, lower) = try mp.hemispheres(energy: 15)
        XCTAssertEqual(upper.count, n); XCTAssertEqual(lower.count, n)
        XCTAssertEqual(Set(upper), [5]); XCTAssertEqual(Set(lower), [105])
        let highest = try mp.hemispheres(energy: nil)
        XCTAssertEqual(Set(highest.upper), [10]); XCTAssertEqual(Set(highest.lower), [110])

        // The refinement's master: the two hemispheres of one energy as Floats, 8 MB.
        let master = try EBSDRefinement.Master(mp, energy: 12)
        XCTAssertEqual((master.upper.count + master.lower.count) * MemoryLayout<Float>.stride, 8_016_008)
        XCTAssertEqual(master.side, side)
    }

    func testValuesJoinOnlyAlike() {
        let a = MasterPatternValues(.uint8([1, 2])), b = MasterPatternValues(.uint8([3]))
        XCTAssertEqual(MasterPatternValues.joined([a, b]), MasterPatternValues(.uint8([1, 2, 3])))
        XCTAssertNil(MasterPatternValues.joined([a, MasterPatternValues([Float(3)])]))
        XCTAssertEqual(MasterPatternValues(.uint16([7, 65_535])).floats(1 ..< 2), [65_535])
        XCTAssertEqual(MasterPatternValues(.uint16([7, 65_535])).byteCount, 4)
    }
}
