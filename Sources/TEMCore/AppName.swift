//
//  AppName.swift
//  Role: the app's name as the person sees it, read from the bundle: "Electron Microscopy Studio" (menu bar "Microscopy
//        Studio") in both builds since 2.1.1 (#759; App Review refuses "Mac" in an app's name, guideline 5.2.5), set in
//        Config/Version.xcconfig. Files the app writes name it too (`writer`, #764).
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

    /// The writer every file the app writes names: CSV and report headers, the `.ang` operator, the `.ctf` project and author,
    /// an `.msa` creator, a run's record. Fixed, not read from the bundle, so a file's bytes do not depend on the build (#764;
    /// up to 2.1.0 files said "macEM").
    public static let writer = "Electron Microscopy Studio"
}
