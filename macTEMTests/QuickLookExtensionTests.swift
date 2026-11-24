//
//  QuickLookExtensionTests.swift
//  Quick Look for dm3, dm4, mrc, emd and ser files (#903): the built app embeds a thumbnail and a preview extension, each answers
//  for the same five content types, and the app declares each of them as an imported type with its file extension (Quick Look
//  matches on content type, never on the extension); .emd conforms to HDF5, so its more specific type wins over 4DSTEM Studio's
//  HDF5 extension. Each extension's versions are the app's, as App Store validation requires. These read the BUILT host app; the
//  pixels and the card are EMSuiteUI's (ShellQuickLookTests) and the reading is FormatoKit's Peek (its pins against RosettaSciIO).
//  Red before: the app had no PlugIns folder and declared no imported type.
//

import XCTest

nonisolated final class QuickLookExtensionTests: XCTestCase {

    /// The five types and the file extension each one is.
    private static let types: [String: String] = [
        "com.gatan.dm3": "dm3", "com.gatan.dm4": "dm4", "org.ccpem.mrc": "mrc", "com.emdatasets.emd": "emd", "com.fei.tia.ser": "ser",
    ]

    private func info(ofExtension name: String) throws -> [String: Any] {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/PlugIns/\(name).appex/Contents/Info.plist")
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any], name)
    }

    /// Mutation: a type left out of either plist, a point identifier swapped, the preview not data-based - red.
    func testBothExtensionsAnswerForTheFiveTypes() throws {
        for (name, point, provider) in [("QuickLookThumbnail", "com.apple.quicklook.thumbnail", "ThumbnailProvider"),
                                        ("QuickLookPreview", "com.apple.quicklook.preview", "PreviewProvider")] {
            let plist = try info(ofExtension: name)
            let ext = try XCTUnwrap(plist["NSExtension"] as? [String: Any], name)
            XCTAssertEqual(ext["NSExtensionPointIdentifier"] as? String, point, name)
            XCTAssertEqual(ext["NSExtensionPrincipalClass"] as? String, "\(name).\(provider)", name)
            let attributes = try XCTUnwrap(ext["NSExtensionAttributes"] as? [String: Any], name)
            XCTAssertEqual(Set(attributes["QLSupportedContentTypes"] as? [String] ?? []), Set(Self.types.keys), name)
            if name == "QuickLookPreview" { XCTAssertEqual(attributes["QLIsDataBasedPreview"] as? Bool, true) }
        }
    }

    /// Mutation: a type no longer declared, declared as exported, with another extension, or .emd not under HDF5 - red.
    func testTheAppImportsEachTypeWithItsFileExtension() throws {
        XCTAssertNil(Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations"), "a format this app does not own is imported")
        let declared = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "UTImportedTypeDeclarations") as? [[String: Any]])
        let byIdentifier = Dictionary(uniqueKeysWithValues: declared.compactMap { entry in
            (entry["UTTypeIdentifier"] as? String).map { ($0, entry) }
        })
        for (identifier, fileExtension) in Self.types {
            let entry = try XCTUnwrap(byIdentifier[identifier], "\(identifier) is not declared")
            let tags = entry["UTTypeTagSpecification"] as? [String: Any]
            XCTAssertEqual(tags?["public.filename-extension"] as? [String], [fileExtension], identifier)
        }
        XCTAssertEqual(byIdentifier["com.emdatasets.emd"]?["UTTypeConformsTo"] as? [String], ["org.hdfgroup.hdf5"])
        XCTAssertNotNil(byIdentifier["org.hdfgroup.hdf5"], "the type .emd conforms to is declared too")
    }

    /// App Store validation refuses an extension whose versions are not its app's. Mutation: a version set in one target - red.
    func testEachExtensionCarriesTheAppsVersions() throws {
        for name in ["QuickLookThumbnail", "QuickLookPreview"] {
            let plist = try info(ofExtension: name)
            for key in ["CFBundleShortVersionString", "CFBundleVersion"] {
                XCTAssertEqual(plist[key] as? String, Bundle.main.object(forInfoDictionaryKey: key) as? String, "\(name) \(key)")
            }
            XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.mac4dstem.macTEM.\(name)")
        }
    }
}
