//
//  SoftwareUpdateTests.swift
//  The website download's updater (#583, as mac4DSTEM#122): Sparkle in that build only. The App Store build reads Info.plist and
//  macTEM.entitlements; the download reads Info-Direct.plist and macTEM-Direct.entitlements (MACEM_STORE_BUILD=NO). These hold the
//  two pairs to differ by exactly the updater's keys, the project to switch on that one setting, and the release scripts to sign
//  the download's updater, write its feed and refuse the updater in the store build.
//

import XCTest
@testable import macTEM

nonisolated final class SoftwareUpdateTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()

    private func plist(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: root.appendingPathComponent(path))
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any], path)
    }

    private func text(_ path: String) throws -> String {
        try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Mutation: edit Info.plist without copying the change, drop a Sparkle key, or turn system profiling or automatic checks on
    /// without asking - red.
    func testTheDownloadsInfoPlistIsTheStoresPlusTheUpdaterKeys() throws {
        let store = try plist("macTEM/Info.plist")
        var direct = try plist("macTEM/Info-Direct.plist")
        XCTAssertEqual(direct.removeValue(forKey: "SUFeedURL") as? String, "https://mac4dstem.com/appcast/macem.xml")
        let key = try XCTUnwrap(direct.removeValue(forKey: "SUPublicEDKey") as? String)
        XCTAssertEqual(key, "j4qRIz2RC40tuHy7FRngpvq0OHuJWLjAT7v/Mtx49qE=", "the public half of Paul's EdDSA key, mac4DSTEM's feed's too")
        XCTAssertEqual(direct.removeValue(forKey: "SUEnableInstallerLauncherService") as? Bool, true, "the sandboxed installer")
        XCTAssertEqual(direct.removeValue(forKey: "SUEnableSystemProfiling") as? Bool, false, "no system profile is sent")
        XCTAssertEqual(direct.removeValue(forKey: "SUBundleName") as? String, "Electron Microscopy Studio",
                       "a normalized install takes the full name, not the menu bar's (#759)")
        XCTAssertNil(direct["SUEnableAutomaticChecks"], "Sparkle asks the person before it checks by itself")
        XCTAssertEqual(NSDictionary(dictionary: direct), NSDictionary(dictionary: store), "Info-Direct.plist is Info.plist plus the five Sparkle keys")
        XCTAssertTrue(store.keys.allSatisfy { !$0.hasPrefix("SU") }, "the store build names no updater")
    }

    /// Both builds reach the Materials Project (#778); the download adds only the installer exception. Mutation: give the store build
    /// the installer exception, or the download any other extra entitlement - red.
    func testTheDownloadsEntitlementsAreTheStoresPlusTheUpdatersOwn() throws {
        let store = try plist("macTEM/macTEM.entitlements")
        var direct = try plist("macTEM/macTEM-Direct.entitlements")
        let names = try XCTUnwrap(direct.removeValue(forKey: "com.apple.security.temporary-exception.mach-lookup.global-name") as? [String])
        XCTAssertEqual(names, ["$(PRODUCT_BUNDLE_IDENTIFIER)-spks", "$(PRODUCT_BUNDLE_IDENTIFIER)-spki"])
        XCTAssertEqual(NSDictionary(dictionary: direct), NSDictionary(dictionary: store))
        XCTAssertEqual(store["com.apple.security.network.client"] as? Bool, true, "the feed and the Materials Project share the one outgoing permission")
    }

    /// Mutation: a configuration that forgets the switch, or a store build that keeps the framework - red.
    func testTheProjectSwitchesTheUpdaterOnTheStoreBuildSetting() throws {
        let project = try text("macTEM.xcodeproj/project.pbxproj")
        func count(_ line: String) -> Int { project.components(separatedBy: line).count - 1 }
        // Debug, Release and Develop of the app target.
        XCTAssertEqual(count("MACEM_STORE_BUILD = NO;"), 3)
        XCTAssertEqual(count(#"INFOPLIST_FILE = "macTEM/Info$(MACEM_FLAVOUR_SUFFIX_$(MACEM_STORE_BUILD)).plist";"#), 3)
        XCTAssertEqual(count(#"CODE_SIGN_ENTITLEMENTS = "macTEM/macTEM$(MACEM_FLAVOUR_SUFFIX_$(MACEM_STORE_BUILD)).entitlements";"#), 3)
        XCTAssertEqual(count(#"SWIFT_ACTIVE_COMPILATION_CONDITIONS = "$(inherited) $(MACEM_UPDATER_CONDITION_$(MACEM_STORE_BUILD))";"#), 3)
        XCTAssertEqual(count("MACEM_UPDATER_CONDITION_NO = SPARKLE;"), 3)
        // -dead_strip_dylibs alone would also drop the three HDF5 frameworks' load commands (FormatoKit opens them by path): they are
        // kept as needed, so the store executable differs from the download's only by Sparkle.
        XCTAssertEqual(count(#"MACEM_STORE_LDFLAGS_YES = "-Wl,-dead_strip_dylibs -Wl,-needed_framework,FormatoLibHDF5 -Wl,-needed_framework,FormatoLibSZ -Wl,-needed_framework,FormatoLibAEC";"#), 3)
        XCTAssertTrue(project.contains(#"rm -rf \"${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}/Sparkle.framework\""#))
        XCTAssertTrue(project.contains(#""Info-Direct.plist","#), "the download's plist is not copied as a resource")
    }

    /// FormatoKit's HDF5 frameworks arrive signed by another Team ID, and a Release build's hardened runtime refuses them at launch
    /// (#1001). The pbxproj cannot be built here, so this reads it: a phase of the app target re-signs the three frameworks with the
    /// app's identity. Mutation: the phase, a framework or the identity left out - red.
    func testTheProjectResignsTheEmbeddedHDF5FrameworksWithTheAppsIdentity() throws {
        let project = try text("macTEM.xcodeproj/project.pbxproj")
        XCTAssertEqual(project.components(separatedBy: "Sign the HDF5 frameworks with the app's identity").count - 1, 3,
                       "the phase is defined once and listed once in the app target")
        XCTAssertTrue(project.contains("for library in FormatoLibHDF5 FormatoLibSZ FormatoLibAEC; do"))
        XCTAssertTrue(project.contains(#"codesign --force --sign \"${EXPANDED_CODE_SIGN_IDENTITY}\" --options runtime"#))
    }

    /// Mutation: drop the helper signing, the key check or the feed step from the download; or the store's updater checks - red.
    func testTheReleaseScriptsSignTheDownloadsUpdaterAndRefuseItInTheStore() throws {
        let download = try text("tools/release.sh")
        for check in ["Installer.xpc", "Autoupdate", "Updater.app", "Downloader.xpc", "SUPublicEDKey", "SET-BEFORE-RELEASE",
                      "-clonedSourcePackagesDirPath", "CURRENT_PROJECT_VERSION=\"$EXPECTED\"", "mach-lookup", "tools/appcast.sh",
                      // The new name from the project's setting, and the old names' copies, so old download links keep working (#759).
                      "MACEM_APP_NAME_NO", #"cp "$DMG" "$OUT/$FILE.dmg""#, #"cp "$DMG" "$OUT/macEM.dmg""#, #"cp "$DMG" "$OUT/macTEM.dmg""#] {
            XCTAssertTrue(download.contains(check), "release.sh no longer handles \(check)")
        }
        let feed = try text("tools/appcast.sh")
        for part in ["sign_update", "sparkle:version", "sparkle:minimumSystemVersion", "releases/download/{tag}/Electron-Microscopy-Studio-{version}.dmg",
                     "macTEM.xcodeproj/project.pbxproj"] {
            XCTAssertTrue(feed.contains(part), "appcast.sh no longer writes \(part)")
        }
        let store = try text("tools/release-store.sh")
        for check in ["Sparkle.framework", "SUFeedURL", "otool -L"] {
            XCTAssertTrue(store.contains(check), "release-store.sh no longer checks \(check)")
        }
    }

    /// Mutation: start the updater in a Debug build, under UI tests, or with the placeholder key - red.
    func testTheUpdaterStartsOnlyInAReleaseWithARealKey() {
        let real: [String: Any] = ["SUFeedURL": "https://mac4dstem.com/appcast/macem.xml", "SUPublicEDKey": "c2lnbmluZy1rZXk="]
        XCTAssertTrue(SoftwareUpdatePolicy.shouldStart(info: real, debugBuild: false, uiTesting: false))
        XCTAssertFalse(SoftwareUpdatePolicy.shouldStart(info: real, debugBuild: true, uiTesting: false))
        XCTAssertFalse(SoftwareUpdatePolicy.shouldStart(info: real, debugBuild: false, uiTesting: true))
        var placeholder = real
        placeholder["SUPublicEDKey"] = SoftwareUpdatePolicy.placeholderKey
        XCTAssertFalse(SoftwareUpdatePolicy.shouldStart(info: placeholder, debugBuild: false, uiTesting: false))
        XCTAssertFalse(SoftwareUpdatePolicy.shouldStart(info: [:], debugBuild: false, uiTesting: false), "the store build's plist")
    }
}
