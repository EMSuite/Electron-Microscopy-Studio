//
//  GeneratedFiles.swift
//  Files written for a test, of the sizes a test asks for: a GMS DM4 spectrum image (EDS or EELS), an EDAX `.up2` pattern scan with
//  its `.ang`, a lone `.ang` map. Shared by RoomMemoryTests (each room gives a closed file's memory back) and BenchmarkTests (the
//  nightly timings). No test is declared here (the unit gate reads test names by file and type).
//

import Foundation

nonisolated enum GeneratedFiles {

    /// A GMS DM4 spectrum image of `nx` × `ny` × `channels` int16 values, as `DM4TestFile` writes one: named "EDS SI" or "EELS SI"
    /// (the name gives the object its role, as GMS names do), the energy axis in keV (EDS, 10 eV a channel) or eV (EELS, 0.25 eV a
    /// channel, zero at channel 40). Stored x fastest and energy slowest, as GMS writes it.
    static func spectrumImage(eels: Bool, nx: Int, ny: Int, channels: Int, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent("\(eels ? "eels" : "eds")-\(nx)x\(ny)x\(channels).dm4")
        let data: Data = autoreleasepool {
            let plane = nx * ny
            var values = [Int16](repeating: 0, count: plane * channels)
            for c in 0..<channels {
                let level: Int16
                if eels {
                    let zlp = 20_000 * exp(-0.5 * pow(Double(c - 40) / 2.5, 2)), plasmon = 600 * exp(-0.5 * pow(Double(c - 100) / 12, 2))
                    level = Int16(zlp + plasmon + 20)
                } else {
                    let al = 40 * exp(-0.5 * pow(Double(c - 149) / 4, 2)), si = 15 * exp(-0.5 * pow(Double(c - 174) / 4, 2))
                    level = Int16(al + si + (c > 20 ? 2 : 0))
                }
                for p in 0..<plane { values[c * plane + p] = level &+ Int16(p % 3) }
            }
            let energy = eels ? DM4TestFile.Axis(origin: 40, scale: 0.25, units: "eV") : DM4TestFile.Axis(origin: 0, scale: 0.01, units: "keV")
            let scan = DM4TestFile.Axis(origin: 0, scale: 2, units: "nm")
            let object = DM4TestFile.object(name: eels ? "EELS SI" : "EDS SI", dims: [Int32(nx), Int32(ny), Int32(channels)],
                                            axes: [scan, scan, energy], pixels: values, voltage: 200_000)
            return DM4TestFile.file([object])
        }
        try data.write(to: url)
        return url
    }

    /// An EDAX scan: `<stem>.up2` (version 3, a square grid of `rows` × `columns` patterns of `side` × `side` uint16) and, when `ang`,
    /// the `.ang` of the same points beside it (the fixture's header, Ni, on 1.5 µm steps).
    static func edaxScan(rows: Int, columns: Int, side: Int, ang: Bool, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent("scan-\(rows)x\(columns).up2")
        var header = Data()
        func word(_ v: Int) { withUnsafeBytes(of: UInt32(v).littleEndian) { header.append(contentsOf: $0) } }
        word(3); word(side); word(side); word(42)
        header.append(0)
        word(columns); word(rows)
        header.append(0)
        for step in [1.5, 1.5] { withUnsafeBytes(of: step.bitPattern.littleEndian) { header.append(contentsOf: $0) } }
        precondition(header.count == 42)
        let count = rows * columns * side * side
        var body = Data(count: count * 2)
        body.withUnsafeMutableBytes { raw in
            let out = raw.bindMemory(to: UInt16.self)
            for i in 0..<(rows * columns) {
                let theta = Double(i % 7) * 0.4
                let (c, s) = (cos(theta), sin(theta))
                for y in 0..<side {
                    for x in 0..<side {
                        let u = Double(x - side / 2) * c + Double(y - side / 2) * s
                        let band = abs(u.truncatingRemainder(dividingBy: 24)) < 4 ? 600.0 : 0
                        out[(i * side + y) * side + x] = UInt16(2000 + band + Double((x * 7 + y * 3 + i) % 50)).littleEndian
                    }
                }
            }
        }
        try (header + body).write(to: url)
        if ang { try angText(rows: rows, columns: columns).write(to: url.deletingPathExtension().appendingPathExtension("ang"), atomically: true, encoding: .utf8) }
        return url
    }

    /// A lone `.ang` of `rows` × `columns` points: no pattern file beside it, so it opens in the Maps room.
    static func loneMap(rows: Int, columns: Int, in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent("map-\(rows)x\(columns).ang")
        try angText(rows: rows, columns: columns).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// The fixture `ebsd-tsl.ang`'s header with the grid made `rows` × `columns` on 1.5 µm steps, and a point per row of the grid: the
    /// orientation turning across the map, phase 1, IQ and CI that vary.
    private static func angText(rows: Int, columns: Int) throws -> String {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/ebsd-tsl.ang")
        var lines: [String] = []
        for line in try String(contentsOf: fixture, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false) where line.hasPrefix("#") {
            if line.contains("XSTEP:") { lines.append("# XSTEP: 1.500000") }
            else if line.contains("YSTEP:") { lines.append("# YSTEP: 1.500000") }
            else if line.contains("NCOLS_ODD:") { lines.append("# NCOLS_ODD: \(columns)") }
            else if line.contains("NCOLS_EVEN:") { lines.append("# NCOLS_EVEN: \(columns)") }
            else if line.contains("NROWS:") { lines.append("# NROWS: \(rows)") }
            else { lines.append(String(line)) }
        }
        lines.reserveCapacity(lines.count + rows * columns)
        for row in 0..<rows {
            for column in 0..<columns {
                let phi1 = Double((row / 10 + column / 10) % 60) * 0.1, iq = 100 + Double((row * 3 + column) % 97)
                lines.append("  \(phi1)  0.5  1.0  \(Double(column) * 1.5)  \(Double(row) * 1.5)  \(iq)  0.8  1  1000  0.5")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
