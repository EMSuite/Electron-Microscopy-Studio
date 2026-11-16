//
//  AppName.swift
//  Role: the app's name as the person sees it, read from the bundle. The website build is "macEM"; the App Store build is
//        "Electron Microscopy Studio" (menu bar "Microscopy Studio"), because App Review refuses "Mac" in an app's name
//        (guideline 5.2.5; mac4DSTEM 5.2.0 rejected 16 Nov 2026). Both names are set in Config/Version.xcconfig, so a
//        sentence on screen names the build the person runs. Files the app writes keep "macEM" as their software and
//        author: that is the project's name, which provenance and readers rely on.
//

import Foundation

public nonisolated enum AppName {
    /// "macEM" or "Electron Microscopy Studio": CFBundleDisplayName, else CFBundleName, else the project's name. Only an
    /// app's own bundle names it: under `swift test` the main bundle is the xctest tool.
    public static let display: String = Bundle.main.bundleURL.pathExtension == "app"
        ? display(from: Bundle.main.infoDictionary) : "macEM"

    /// Pure, so it is tested.
    public static func display(from info: [String: Any]?) -> String {
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = info?[key] as? String, !name.isEmpty { return name }
        }
        return "macEM"
    }
}
