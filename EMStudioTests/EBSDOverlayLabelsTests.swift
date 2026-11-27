//
//  EBSDOverlayLabelsTests.swift
//  The EBSD overlays' labels never meet (#1059, the pass of 25 Nov 2026 on the Ni demo): the Indexing room's band families were drawn at
//  each band's middle, so the bands through one zone axis stacked their `{hkl}` plates on one point; the Maps room's slip-trace planes
//  were drawn just past each trace's end, so a small grain in the map's corner piled its three `{111}` plates on each other and on the
//  picked point's marker. `EBSDOverlayLabels` places from the strongest down, each where it fits inside the picture and clear of the
//  others and of the marker. Red before: no `EBSDOverlayLabels`, and the old spots (the middles, the ends plus 3 pt) overlap below.
//

import CoreGraphics
import Foundation
import XCTest
@testable import EMStudio

nonisolated final class EBSDOverlayLabelsTests: XCTestCase {
    /// A `{022}` plate in caption2 with the overlay's padding, near enough for the geometry.
    private let bandPlate = CGSize(width: 46, height: 19)

    /// Ten bands across a 300 pt pattern, strongest first, six of them through one zone axis at its centre (the demo's pattern has its
    /// bands meet at the pattern centre the same way), the rest crossing them.
    private let bands: [(CGPoint, CGPoint)] = [
        (CGPoint(x: 0, y: 150), CGPoint(x: 300, y: 150)),
        (CGPoint(x: 150, y: 0), CGPoint(x: 150, y: 300)),
        (CGPoint(x: 0, y: 0), CGPoint(x: 300, y: 300)),
        (CGPoint(x: 300, y: 0), CGPoint(x: 0, y: 300)),
        (CGPoint(x: 0, y: 116.3), CGPoint(x: 300, y: 225.5)),
        (CGPoint(x: 129, y: 0), CGPoint(x: 238.2, y: 300)),
        (CGPoint(x: 300, y: 95.4), CGPoint(x: 0, y: 204.6)),
        (CGPoint(x: 136.4, y: 0), CGPoint(x: 27.2, y: 300)),
        (CGPoint(x: 0, y: 94.5), CGPoint(x: 300, y: 267.7)),
        (CGPoint(x: 0, y: 123.6), CGPoint(x: 300, y: 176.4)),
    ]

    private func noTwoMeet(_ frames: [CGRect], file: StaticString = #filePath, line: UInt = #line) {
        for i in frames.indices {
            for j in frames.indices where j > i {
                XCTAssertFalse(frames[i].intersects(frames[j]), "\(frames[i]) meets \(frames[j])", file: file, line: line)
            }
        }
    }

    /// The ten band labels: no two plates intersect, each inside the pattern and on its own band, the strongest at its band's middle.
    func testNoTwoBandLabelsMeet() throws {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 300)
        let old = bands.map { CGRect(x: ($0.0.x + $0.1.x) / 2 - 23, y: ($0.0.y + $0.1.y) / 2 - 9.5, width: 46, height: 19) }
        XCTAssertTrue(old.indices.contains { i in old.indices.contains { j in j > i && old[i].intersects(old[j]) } },
                      "setup: at the middles the plates stack")

        let placed = EBSDOverlayLabels.place(sizes: Array(repeating: bandPlate, count: bands.count),
                                             spots: bands.map { EBSDOverlayLabels.bandSpots(from: $0.0, to: $0.1) }, in: bounds)
        XCTAssertGreaterThanOrEqual(placed.count, 8, "most bands keep their label")
        noTwoMeet(placed.map(\.frame))
        for label in placed {
            XCTAssertTrue(bounds.contains(label.frame), "inside the pattern")
            let (a, b) = bands[label.index]
            let centre = CGPoint(x: label.frame.midX, y: label.frame.midY)
            XCTAssertLessThan(EBSDOverlayLabels.distance(centre, toSegment: a, b), 0.5, "band \(label.index) sits on its line")
        }
        let first = try XCTUnwrap(placed.first)
        XCTAssertEqual(first.index, 0)
        XCTAssertEqual(first.frame.midX, 150, accuracy: 0.01, "the strongest band keeps its middle")
        XCTAssertEqual(placed.map(\.index), placed.map(\.index).sorted(), "placed from the strongest down")
    }

    /// A label with no free spot is left out, never drawn over another.
    func testALabelWithNoRoomIsLeftOut() {
        let bounds = CGRect(x: 0, y: 0, width: 60, height: 30)
        let spot = [[CGPoint(x: 30, y: 15)]]
        let placed = EBSDOverlayLabels.place(sizes: [bandPlate, bandPlate], spots: spot + spot, in: bounds)
        XCTAssertEqual(placed.map(\.index), [0])
        XCTAssertTrue(EBSDOverlayLabels.place(sizes: [CGSize(width: 80, height: 19)], spots: spot, in: bounds).isEmpty, "wider than the picture")
    }

    /// Grain 1 in the top-left corner of a 60 × 60 map drawn 400 pt wide, with three slip traces through its centroid and the picked point
    /// on it (the demo's case: no grain picked by the person, the pick at the scan's first point): every trace keeps its label, inside the
    /// map, beside its own trace, clear of the others and of the marker.
    func testTheTraceLabelsOfAGrainInTheCornerDoNotPile() {
        let scale: CGFloat = 400 / 60
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 400)
        let centroid = CGPoint(x: 2.5 * scale, y: 2 * scale)
        let half = 3 * scale
        let traces = [0.0, 60.0, 120.0].map { degrees -> (CGPoint, CGPoint) in
            let a = degrees * Double.pi / 180
            let d = CGPoint(x: CGFloat(cos(a)) * half, y: CGFloat(sin(a)) * half)
            return (CGPoint(x: centroid.x - d.x, y: centroid.y - d.y), CGPoint(x: centroid.x + d.x, y: centroid.y + d.y))
        }
        let plate = CGSize(width: 38, height: 16)
        let marker = CGRect(x: centroid.x - 10, y: centroid.y - 10, width: 20, height: 20)

        // The old spot: just past each trace's end, 3 pt right of it.
        let old = traces.map { CGRect(x: $0.1.x + 3, y: $0.1.y - plate.height / 2, width: plate.width, height: plate.height) }
        XCTAssertTrue(old[1].intersects(old[2]) || old.contains { $0.intersects(marker) } || old.contains { !bounds.contains($0) },
                      "setup: the old labels pile up")

        let placed = EBSDOverlayLabels.place(sizes: Array(repeating: plate, count: traces.count),
                                             spots: traces.map { EBSDOverlayLabels.traceSpots(from: $0.0, to: $0.1, size: plate) },
                                             in: bounds, avoiding: [marker])
        XCTAssertEqual(placed.map(\.index), [0, 1, 2], "every trace keeps its label")
        noTwoMeet(placed.map(\.frame))
        for label in placed {
            XCTAssertTrue(bounds.contains(label.frame), "inside the map")
            XCTAssertFalse(label.frame.intersects(marker), "clear of the picked point's marker")
            let (a, b) = traces[label.index]
            let centre = CGPoint(x: label.frame.midX, y: label.frame.midY)
            XCTAssertLessThan(EBSDOverlayLabels.distance(centre, toSegment: a, b), 60, "trace \(label.index)'s label sits beside it")
            XCTAssertFalse(label.frame.insetBy(dx: 1, dy: 1).contains(CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)), "not on the trace's middle")
        }
    }

    /// The rooms draw through the placement: the band families and the slip planes alike.
    func testTheOverlaysPlaceTheirLabels() throws {
        let indexing = try FFTRoomWiringTests.squeezedUI("IndexingRoom.swift")
        XCTAssertTrue(indexing.contains("EBSDOverlayLabels.bandSpots(from: point(band.start ?? .zero), to: point(band.end ?? .zero))"))
        XCTAssertTrue(indexing.contains("for placed in EBSDOverlayLabels.place(sizes: plates, spots: spots, in: CGRect(origin: .zero, size: size))"))
        XCTAssertFalse(indexing.contains(".position(point((start + end) / 2))"), "no label at a band's bare middle")
        // The Maps room's slip traces carry no plates on the map since #1095 (a grain's thirty plates piled over its corner): the Slip
        // table in the bottom area names each plane beside its trace's colour, angle and colour word.
        let maps = try FFTRoomWiringTests.squeezedUI("MapsRoomAnalysis.swift")
        let overlay = try XCTUnwrap(maps.components(separatedBy: "struct MapsAnalysisOverlay: View {").dropFirst().first?
            .components(separatedBy: "private var spokenLabel: String {").first)
        XCTAssertFalse(overlay.contains("EBSDOverlayLabels."), "no plate on the map")
        XCTAssertFalse(overlay.contains("context.draw("), "no word drawn on the map")
        XCTAssertFalse(maps.contains("x: end.x + 3"), "no label at a trace's bare end")
        XCTAssertTrue(maps.contains("TableColumn(\"Plane\", value: \\.id)"), "the Slip table names the planes")
    }
}
