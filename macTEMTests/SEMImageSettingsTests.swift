//
//  SEMImageSettingsTests.swift
//  The SEM image display's one stored switch (`SEMImageSettings`, #341; in Settings > Images since #626): the vendor's databar is
//  hidden unless the person chose to show it, and the choice is kept under the key it has had since #341, so a choice made in an
//  earlier version is read as it was. Each test has defaults of its own, removed after it; none touches the app's.
//  Red under: shown by default, another key, the choice read as anything but a Boolean.
//

import XCTest
@testable import macTEM

nonisolated final class SEMImageSettingsTests: XCTestCase {

    /// Defaults of the test's own, removed after it.
    private func scratchDefaults() throws -> UserDefaults {
        let suite = "mactem-sem-image-settings-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testTheDatabarIsHiddenUnlessThePersonChoseToShowIt() {
        XCTAssertTrue(SEMImageSettings.cropDatabarDefault, "hidden by default")
    }

    /// The key is the one #341 wrote, a Boolean: what an earlier build stored is what `@AppStorage` reads.
    func testTheChoiceIsKeptUnderItsKey() throws {
        XCTAssertEqual(SEMImageSettings.cropDatabarKey, "sem.cropDatabar")
        let defaults = try scratchDefaults()
        defaults.set(false, forKey: "sem.cropDatabar")
        XCTAssertEqual(defaults.object(forKey: SEMImageSettings.cropDatabarKey) as? Bool, false)
    }
}
