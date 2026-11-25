//
//  HelpMenuLinks.swift
//  Role: What the Help menu opens (#753, plan row Q13 of 2.3): the app's documentation on the website (first, ⌘?), the tutorials, the
//        example data and the release notes, then Support and Send Feedback…; Report a Problem… opens EMSuiteUI's report window. The
//        content lives on the website, where it is versioned and searchable, and the menu links to it, in place of a Help book (#630).
//        Every address is a page the website serves (EMSuite/website: docs/electron-microscopy-studio/index.html,
//        docs/tasks/index.html, docs/data/index.html, suite/releases.html, support.html). The welcome canvas's Tutorials link is the
//        same address (#802).
//

import Foundation
import TEMCore

nonisolated enum HelpMenuLinks {
    /// One item: the title the menu shows and the address it opens in the person's browser.
    nonisolated struct Link: Identifiable, Equatable, Sendable {
        let title: String
        let url: URL
        var id: String { title }
    }

    static let site = "https://mac4dstem.com"

    /// The app's documentation, the menu's first item (⌘?), in place of the system's Help book item.
    static let help = Link(title: "\(AppName.display) Help", url: URL(string: site + "/docs/electron-microscopy-studio/")!)
    /// One page per task, each in three steps: the tutorials index. The welcome canvas links here too.
    static let tutorials = Link(title: "Tutorials", url: URL(string: site + "/docs/tasks/")!)
    /// The public datasets to try the app on, and the demo data it ships.
    static let exampleData = Link(title: "Example Data", url: URL(string: site + "/docs/data/")!)
    /// Every release of both apps and the kits, with its notes.
    static let releaseNotes = Link(title: "Release Notes", url: URL(string: site + "/suite/releases.html")!)
    /// The support page: e-mail, the GitHub issues and the troubleshooting pages.
    static let support = Link(title: "\(AppName.display) Support", url: URL(string: site + "/support.html")!)
    /// A message to the author from the person's own mail app, its subject naming the app.
    static let sendFeedback = Link(title: "Send Feedback…", url: feedbackMail(subject: "\(AppName.display) feedback"))

    /// The documentation group under the Help item.
    static let guides: [Link] = [tutorials, exampleData, releaseNotes]
    /// The group above Report a Problem….
    static let contact: [Link] = [support, sendFeedback]

    /// Every item the menu opens in the browser or the mail app, in the menu's order.
    static var all: [Link] { [help] + guides + contact }

    /// `mailto:` the project's address with `subject`, percent-encoded.
    static func feedbackMail(subject: String) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "mail@mac4dstem.com"
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        return components.url!
    }
}
