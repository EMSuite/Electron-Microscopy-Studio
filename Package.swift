// swift-tools-version: 6.2
// SPDX-License-Identifier: GPL-3.0-only
// TEMCore and TEMSession, the app's two library targets (`tools/run-tests.sh core` builds them standalone: the layering
// gate). Kits and MacEMUI by version range (Package.resolved holds the versions built). No UI below the app: TEMCore takes only ShellEDXModel (the shared EDS room's model) and ShellExport (figures and the methods record) from MacEMUI, neither with SwiftUI.
import PackageDescription

let package = Package(
    name: "macTEM",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "TEMCore", targets: ["TEMCore"]),
        .library(name: "TEMSession", targets: ["TEMSession"]),
    ],
    dependencies: [
        .package(url: "https://github.com/EMSuite/FormatoKit", from: "0.22.0"),
        .package(url: "https://github.com/EMSuite/DiffractoKit", from: "0.24.2"),
        .package(url: "https://github.com/EMSuite/ImagoKit", from: "0.12.0"),
        .package(url: "https://github.com/EMSuite/SpectroKit", from: "0.17.2"),
        // The window shell, controls and Metal image view both apps share. TEMSession takes ShellMetal (MetalEngine, ColormapKind); TEMCore and
        // TEMSession take ShellEDXModel (the shared EDS room; the EELS room reuses its regions and pins).
        .package(url: "https://github.com/EMSuite/EMSuiteUI", from: "0.20.1"),
        // The Simulation document's specimen and HRTEM image (2.5): the slab builder, the multislice and the transfer function.
        .package(url: "https://github.com/EMSuite/SimulatoKit", from: "0.8.1"),
    ],
    targets: [
        .target(
            name: "TEMCore",
            dependencies: [
                .product(name: "Formato", package: "FormatoKit"),
                .product(name: "FormatoCore", package: "FormatoKit"),
                .product(name: "FormatoDM", package: "FormatoKit"),
                .product(name: "FormatoEMD", package: "FormatoKit"),
                .product(name: "FormatoHDF5", package: "FormatoKit"),
                .product(name: "FormatoHSPY", package: "FormatoKit"),
                .product(name: "FormatoMRC", package: "FormatoKit"),
                .product(name: "FormatoMSA", package: "FormatoKit"),
                .product(name: "FormatoTIA", package: "FormatoKit"),
                .product(name: "FormatoTIFF", package: "FormatoKit"),
                .product(name: "DiffractoCore", package: "DiffractoKit"),
                .product(name: "DiffractoScattering", package: "DiffractoKit"),
                .product(name: "DiffractoGeometry", package: "DiffractoKit"),
                .product(name: "DiffractoOrientation", package: "DiffractoKit"),
                .product(name: "ImagoCore", package: "ImagoKit"),
                .product(name: "ImagoFFT", package: "ImagoKit"),
                .product(name: "ImagoFilters", package: "ImagoKit"),
                .product(name: "SpectroCore", package: "SpectroKit"),
                .product(name: "SpectroEDX", package: "SpectroKit"),
                .product(name: "SpectroEELS", package: "SpectroKit"),
                .product(name: "ShellEDXModel", package: "EMSuiteUI"),
                .product(name: "ShellExport", package: "EMSuiteUI"),
                .product(name: "SimulatoCore", package: "SimulatoKit"),
                .product(name: "SimulatoMultislice", package: "SimulatoKit"),
                .product(name: "SimulatoProbe", package: "SimulatoKit"),
                .product(name: "SimulatoDetector", package: "SimulatoKit"),
            ],
            swiftSettings: [
                // Optimised in Debug too.
                .unsafeFlags(["-O"], .when(configuration: .debug)),
                // nonisolated by default: no .defaultIsolation here.
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        .target(
            name: "TEMSession",
            dependencies: [
                "TEMCore",
                .product(name: "FormatoCore", package: "FormatoKit"),
                .product(name: "DiffractoCore", package: "DiffractoKit"),
                .product(name: "DiffractoScattering", package: "DiffractoKit"),
                .product(name: "DiffractoGeometry", package: "DiffractoKit"),
                .product(name: "DiffractoOrientation", package: "DiffractoKit"),
                .product(name: "ImagoCore", package: "ImagoKit"),
                .product(name: "ImagoFFT", package: "ImagoKit"),
                .product(name: "ImagoFilters", package: "ImagoKit"),
                .product(name: "SpectroCore", package: "SpectroKit"),
                .product(name: "SpectroEDX", package: "SpectroKit"),
                .product(name: "SpectroEELS", package: "SpectroKit"),
                .product(name: "ShellMetal", package: "EMSuiteUI"),
                .product(name: "ShellEDXModel", package: "EMSuiteUI"),
            ],
            swiftSettings: [
                .unsafeFlags(["-O"], .when(configuration: .debug)),
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("MemberImportVisibility"),
            ]
        ),
        // The parity harnesses (tools/parity): each is an executable over TEMCore, so the kits are the ones Package.resolved pins.
        // tools/lib/harness.sh builds them; they run in the nightly, never per session.
        parityHarness("DiffractionRoomParity", "diffraction-room-parity",
                      exclude: ["README.md", "plants.py", "reference.py", "ring_calibration_reference.py", "ring_fit_plants.py", "run.sh"],
                      sources: ["main.swift"],
                      kits: [("DiffractoCore", "DiffractoKit"), ("DiffractoScattering", "DiffractoKit"), ("DiffractoGeometry", "DiffractoKit"),
                             ("ImagoCore", "ImagoKit")]),
        parityHarness("ExportParity", "export-parity",
                      exclude: ["README.md", "reference.py", "run.sh"],
                      sources: ["main.swift"],
                      kits: [("ImagoCore", "ImagoKit"), ("ImagoFFT", "ImagoKit")]),
        parityHarness("FFTExportParity", "fft-export-parity",
                      exclude: ["README.md", "reference.py", "run.sh"],
                      sources: ["main.swift"],
                      kits: [("ImagoCore", "ImagoKit"), ("ImagoFFT", "ImagoKit")]),
        parityHarness("MetadataParity", "metadata-parity",
                      exclude: ["README.md", "dm4_writer.py", "make_dm4_fixture.py", "make_fixture.py", "reference.py", "run.sh"],
                      sources: ["main.swift"],
                      kits: [("FormatoCore", "FormatoKit"), ("FormatoDM", "FormatoKit"), ("FormatoMRC", "FormatoKit"), ("FormatoTIFF", "FormatoKit")]),
        parityHarness("ProfileParity", "profile-parity",
                      exclude: ["README.md", "reference.py", "run.sh"],
                      sources: ["main.swift"],
                      kits: [("ImagoCore", "ImagoKit")]),
        // The planting binding is the unit tests' (macTEMTests/TestHDF5Binding.swift), linked here as a symlink.
        parityHarness("SidecarParity", "sidecar-parity",
                      exclude: ["README.md", "dense_fuzz.py", "fixtures", "marks_reference.py", "reference.py", "run.sh"],
                      sources: ["main.swift", "fuzz.swift", "marks.swift", "TestHDF5Binding.swift"],
                      kits: [("FormatoHDF5", "FormatoKit"), ("ImagoCore", "ImagoKit")]),
    ],
    swiftLanguageModes: [.v6]
)

/// A parity harness: an executable over TEMCore at the settings TEMCore builds with (optimised in Debug too, Swift 6, the same
/// upcoming features); `-parse-as-library` because each `main.swift` declares an `@main` type.
func parityHarness(_ name: String, _ folder: String, exclude: [String], sources: [String], kits: [(String, String)]) -> Target {
    .executableTarget(
        name: name,
        dependencies: ["TEMCore"] + kits.map { .product(name: $0.0, package: $0.1) },
        path: "tools/parity/\(folder)",
        exclude: exclude,
        sources: sources,
        swiftSettings: [
            .unsafeFlags(["-O"], .when(configuration: .debug)),
            .unsafeFlags(["-parse-as-library"]),
            .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            .enableUpcomingFeature("InferIsolatedConformances"),
            .enableUpcomingFeature("MemberImportVisibility"),
        ]
    )
}
