//
//  ImageRoomTables.swift
//  Role: the Image room's results under the image and its one Export section (#864). The selected line's profile chart and the found
//        objects (their counts and table) are tabs of the shell's bottom area beside Output (`ImageTable`), as the Diffraction and
//        Maps rooms' tables are: results sit beside the data, never in an inspector section (control placement §1). What the room
//        takes home is one Export section, last and closed, with plain buttons (§4): Figure…, Profile CSV… and Particles CSV….
//        Presentation only: the chart is `MeasureProfileChart`, the table `ParticleTableSheet`, the files `ExportPanels`'s and
//        `ParticleExport`'s.
//

import ImagoCore
import ShellControls
import ShellInspector
import ShellLayout
import SwiftUI
import UniformTypeIdentifiers
import TEMCore
import TEMSession

// MARK: - The tabs under the image

/// One of the Image room's tabs in the bottom area, for the selected file.
struct ImageTablePane: View {
    let table: ImageTable
    @Environment(AppState.self) private var appState

    var body: some View {
        if let item = appState.openItems.selected {
            switch table {
            case .profile: ImageProfilePane(session: item.session, measurements: appState.measurements)
            case .objects: ImageObjectsPane(item: item)
            }
        }
    }
}

/// The words of the tabs before they have something to show. Pure, so a test pins them.
nonisolated enum ImageTableWords {
    static let noProfile = "Draw a line with the Profile tool, or select a profile in Measure, to see the intensity along it."
    static let noObjects = "Show Objects in the Particles section to count and list them here."
}

/// The selected profile's chart across the bottom area: the raw values along the line (never the display window).
private struct ImageProfilePane: View {
    let session: ImageSession
    let measurements: ImageMeasurements

    var body: some View {
        let image = session.imageOrBlank
        if let mark = measurements.mark(measurements.selection), mark.kind == .profile, let profile = measurements.profiles[mark.id] {
            MeasureProfileChart(profile: profile, x: image.x, y: image.y)
                .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .accessibilityIdentifier("image.profile.chart")
        } else {
            ImageTableEmpty(text: ImageTableWords.noProfile)
        }
    }
}

/// The found objects: the counts, sizes and density, then the table (a row outlines its object on the image, ⌘C copies it).
private struct ImageObjectsPane: View {
    let item: OpenItem

    var body: some View {
        if let image = item.session.image, let report = item.particles.report {
            ParticleTableSheet(analysis: item.particles, report: report, scale: ParticleCompute.scale(of: image), embedded: true)
                .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
        } else {
            ImageTableEmpty(text: ImageTableWords.noObjects)
        }
    }
}

/// The counts, sizes and density of the found objects, as the Particles section listed them, above the table.
struct ImageObjectsSummary: View {
    let report: ParticleReport
    let scale: ParticleScale

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ParticleFormat.counts(report.summary))
                .accessibilityIdentifier("particles.counts")
                .accessibilityValue(String(report.summary.counted))
            Text(ParticleFormat.sizes(report.summary, scale: scale)).foregroundStyle(.secondary)
            Text(ParticleFormat.density(report.summary, scale: scale)).foregroundStyle(.secondary)
                .accessibilityIdentifier("particles.density")
            if !scale.isCalibrated {
                Text("The image is not calibrated (or its pixels are not square): sizes are in pixels.").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A tab with nothing to show yet: what to do, centred.
private struct ImageTableEmpty: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("image.table.empty")
    }
}

/// Selects a tab under the image the first time it has something to show (`ImageRoomTools.offer`): Profile when a profile is selected,
/// Objects when objects are found. Hung on the Image room's pane, so it runs only in that room.
struct ImageTableOffers: ViewModifier {
    let item: OpenItem
    @Environment(AppState.self) private var appState

    private var profileSelected: Bool {
        let measurements = appState.measurements
        return measurements.mark(measurements.selection)?.kind == .profile
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: profileSelected, initial: true) { if profileSelected { offer(.profile) } }
            .onChange(of: item.particles.report != nil, initial: true) { if item.particles.report != nil { offer(.objects) } }
    }

    private func offer(_ table: ImageTable) {
        guard appState.navigation.workspaceArea == .image else { return }
        appState.imageRoomTools.offer(table, in: appState.navigation.panels)
    }
}

// MARK: - Export

/// The Image room's exports, one section, last and closed (control placement §2, §4): the figure (File > Export Figure…), the selected
/// profile's samples (File > Export Profile…) and the found objects as CSV, each dimmed with its reason as help.
struct ImageRoomExportSection: View {
    let item: OpenItem
    @Environment(AppState.self) private var appState
    /// The objects' CSV the save panel writes: made when Particles CSV… is pressed and dropped when the panel is done.
    @State private var exportDocument: RoomExportFile?

    private var image: CalibratedImage { item.session.imageOrBlank }

    var body: some View {
        let available = ExportSnapshot.availability(of: appState)
        let loading = appState.imageSession.isLoading
        let report = item.particles.report
        InspectorSection("Export", startsExpanded: false) {
            InspectorActionRow {
                Button("Figure…") { ExportPanels.exportImage(appState: appState) }
                    .disabled(!available.image)
                    .help("The image with its marks and scale bar, as a PDF, SVG or PNG figure (File > Export Figure…)")
                    .accessibilityIdentifier("image.export.figure")
                Button("Profile CSV…") { ExportPanels.exportProfile(appState: appState) }
                    .disabled(!available.profile || loading)
                    .help(available.profile ? "The selected line profile's samples as a CSV file (File > Export Profile…)"
                          : "Select a profile line with samples first")
                    .accessibilityIdentifier("export.profileButton")
            }
            InspectorActionRow {
                Button("Particles CSV…") { exportParticles() }
                    .disabled(report == nil)
                    .help(report == nil ? "The objects need Show Objects first" : "Each found object with its size, shape and note, as a CSV file")
                    .accessibilityIdentifier("particles.export")
            }
        }
        .fileExporter(isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
                      document: exportDocument,
                      contentType: .commaSeparatedText,
                      defaultFilename: ParticleExport.baseName(of: image.fileName)) { result in
            switch result {
            case .success(let url): appState.statusText = "Exported \(url.lastPathComponent)"
            case .failure(let error): appState.present(error)
            }
        }
    }

    /// `--export-dir` (a UI journey) writes without a panel, as the Diffraction readout does; otherwise the save panel, for the CSV
    /// as it is at this press (the one place it is built).
    private func exportParticles() {
        guard let report = item.particles.report else { return }
        let text = ExportSnapshot.particlesCSV(report, image: image, openItems: appState.openItems)
        guard let directory = appState.exportDirectory else {
            exportDocument = RoomExportFile(text: text)
            return
        }
        do {
            let url = try ParticleExport.write(text, imageFileName: image.fileName, into: directory)
            appState.statusText = "Exported \(url.lastPathComponent)"
        } catch { appState.present(error) }
    }
}
