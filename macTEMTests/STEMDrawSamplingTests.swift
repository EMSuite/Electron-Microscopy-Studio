//
//  STEMDrawSamplingTests.swift
//  macTEMTests
//
//  A simulated STEM scan is drawn smooth; a recorded image and every other document keep one block per pixel.
//

import Foundation
import ShellMetal
import TEMSession
import XCTest
@testable import macTEM

final class STEMDrawSamplingTests: XCTestCase {
    /// Red before: every image was drawn nearest, so the Nyquist-step scan read as a checkerboard.
    @MainActor func testOnlyASimulatedSTEMScanIsDrawnSmooth() {
        let simulation = URL(fileURLWithPath: "/macTEM-demo/Simulation 1")
        XCTAssertTrue(ImagePane.drawSampling(of: DemoDocuments.stemURL(of: simulation)) == .linear)
        XCTAssertTrue(ImagePane.drawSampling(of: simulation) == .nearest)
        XCTAssertTrue(ImagePane.drawSampling(of: URL(fileURLWithPath: "/macTEM-demo/HRTEM of Simulation 1")) == .nearest)
        XCTAssertTrue(ImagePane.drawSampling(of: URL(fileURLWithPath: "/Users/someone/recorded STEM of gold.dm4")) == .nearest)
    }

    /// The Image room's view passes it on.
    func testTheImagePanePassesItToTheView() throws {
        let pane = try FFTRoomWiringTests.squeezedUI("ImagePane.swift")
        XCTAssertTrue(pane.contains("sampling: Self.drawSampling(of: item.url)"))
    }
}
