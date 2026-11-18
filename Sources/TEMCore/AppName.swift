//
//  AppName.swift
//  Role: the app's name as the person sees it, read from the bundle: "Electron Microscopy Studio" (menu bar "Microscopy
//        Studio") in both builds since 2.1.1 (#759; App Review refuses "Mac" in an app's name, guideline 5.2.5), set in
//        Config/Version.xcconfig. Files the app writes keep "macEM" as their software and author for now: that is the
//        project's name, which provenance and readers rely on.
//

import Foundation

public nonisolated enum AppName {
    /// "Electron Microscopy Studio": CFBundleDisplayName, else CFBundleName, else the app's name. Only an app's own bundle
    /// names it: under `swift test` the main bundle is the xctest tool.
    public static let display: String = Bundle.main.bundleURL.pathExtension == "app"
        ? display(from: Bundle.main.infoDictionary) : fallback

    /// Pure, so it is tested.
    public static func display(from info: [String: Any]?) -> String {
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = info?[key] as? String, !name.isEmpty { return name }
        }
        return fallback
    }

    /// The name when no bundle states one.
    public static let fallback = "Electron Microscopy Studio"
}
