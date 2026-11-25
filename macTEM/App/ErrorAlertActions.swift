//
//  ErrorAlertActions.swift
//  Role: the error alert's two buttons as data (#1038), so a test pins which one Return presses. HIG, Buttons, Role: "Assign the
//        primary role to the button people are most likely to choose." Dismissing is the likely choice: OK is the default (Return)
//        and the cancel (Esc); Copy Details is the plain button, which puts the alert's text on the pasteboard and closes it. With
//        one cancel button and one other SwiftUI made the other the default, so Return copied (design review 25 Nov 2026).
//

nonisolated enum ErrorAlertAction: CaseIterable {
    case copyDetails, ok

    /// The button's title.
    var title: String {
        switch self {
        case .copyDetails: "Copy Details"
        case .ok: "OK"
        }
    }

    /// The button Return presses (`.keyboardShortcut(.defaultAction)`), drawn as the alert's prominent one.
    var isDefault: Bool { self == .ok }

    /// The button Esc presses (`role: .cancel`).
    var isCancel: Bool { self == .ok }
}
