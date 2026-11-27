//
//  ExportFileNameOption.swift
//  Role: the save panels' "Leave out file names" checkbox (#817): an export carries its methods record, which names the source
//        file, and the file's name is in the export's own header too. On, both name it "source 1", so a figure or a table can be
//        shared without the name of the data behind it. Off by default; the choice is remembered (`ExportMethods.leaveOutFileNamesKey`,
//        read and written by `ExportPanels`). SwiftUI, hosted by `ExportPanels` in the PNG panel's options row or alone under a CSV
//        panel's name field.
//

import SwiftUI

/// What the checkbox is now. Lives as long as its panel does.
@Observable
final class ExportFileNameChoice {
    var leaveOut: Bool

    init(leaveOut: Bool) {
        self.leaveOut = leaveOut
    }
}

/// The checkbox.
struct ExportFileNameOption: View {
    @Bindable var choice: ExportFileNameChoice

    var body: some View {
        Toggle("Leave out file names", isOn: $choice.leaveOut)
            .toggleStyle(.checkbox)
            .help("Name the source “source 1” in the exported file and its methods record, instead of the data file’s name")
            .accessibilityIdentifier("export.leaveOutFileNames")
    }
}

/// The checkbox alone, as a CSV panel's accessory: the PNG panel's padding, so both panels' strips match.
struct ExportFileNameAccessory: View {
    let choice: ExportFileNameChoice

    var body: some View {
        ExportFileNameOption(choice: choice)
            .padding(8)
    }
}
