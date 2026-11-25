//
//  MapsRoomInspector.swift
//  Role: the Maps room's inspector content, mounted by `WorkspaceInspector`'s Settings and Info switches, in the design's map-room order
//        (orientation-maps-room.md §4): Maps (which result the map is, a Source pop-up when the room holds several, D-SEM-99, and what
//        the layer the map pane's heading picks shows, #1065), Phases (the phases with their colours and point groups), Display (a scalar layer's colormap, window and gamma, and
//        whether the map carries the picked point's inset),
//        Misorientation, Grains, Slip and Texture (`MapsRoomAnalysis.swift`), and Export (the map with its key, the grain table, the
//        texture figure). Info: what the map is and how its colours are made (§5). Presentation only: the rows are `MapsRoomFormat`'s,
//        the state `OrientationMapSession`'s.
//

import ShellControls
import ShellInspector
import ShellLayout
import SwiftUI
import TEMCore
import TEMSession

struct MapsRoomSettings: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        let session = appState.maps
        if let document = session.document {
            InspectorSection("Maps") {
                if session.sources.count > 1 {
                    InspectorRow("Source") {
                        Picker("Source", selection: Binding(get: { document.id }, set: { appState.showMapsSource($0) })) {
                            ForEach(session.sources, id: \.id) { held in
                                Text(MapsRoomFormat.sourceTitle(held)).tag(held.id)
                            }
                        }
                        .labelsHidden()
                        .help("Which result the map shows: a map file, the pattern file's own indexing, or the Indexing room's run")
                        .accessibilityIdentifier("maps.source")
                    }
                } else {
                    InspectorValueRow("Source", MapsRoomFormat.sourceWords(document.source))
                        .accessibilityIdentifier("maps.source")
                }
                if let stale = appState.mapsStaleness {
                    InspectorNote(stale).accessibilityIdentifier("maps.source.stale")
                }
                // The map is chosen in the map pane's heading (#1065); here the one line on what it shows.
                InspectorNote(note(session.layer))
                    .accessibilityIdentifier("maps.layer.note")
            }
            InspectorSection("Phases") {
                // The document's own counts, made once when it was read (#690): counting the map's points here ran on every pass
                // of this body, per phase, while an Indexing run landed (#929).
                let phases = MapsRoomFormat.indexedPhases(document.map)
                ForEach(phases, id: \.id) { entry in
                    InspectorValueRow(MapsRoomFormat.phaseName(entry.phase, id: entry.id),
                                      MapsRoomFormat.phasePoints(entry.phase, count: document.phaseCounts[entry.id] ?? 0))
                        .accessibilityIdentifier("maps.phase.\(entry.id)")
                }
                if phases.contains(where: { $0.phase.pointGroup == nil }) {
                    InspectorNote("A phase without a known point group has no IPF colours: its points are black.")
                }
            }
            MapsDisplaySection(session: session, state: appState.mapsRoom)
            MapsMisorientationSection(session: session)
            MapsGrainsSection(session: session)
            MapsSlipSection(session: session)
            MapsTextureSection(session: session)
            MapsExportSection(session: session, state: appState.mapsRoom)
        } else {
            ContentUnavailableView("No orientation map open", systemImage: "map",
                                   description: Text("Open an .ang or .ctf map, an .h5oina saved without patterns, orix's .h5, or an EBSD pattern file that carries one. Its controls appear here."))
        }
    }

    private func note(_ layer: OrientationMapLayer) -> String {
        switch layer {
        case .ipf(let d):
            "The crystal direction along the sample's \(d.rawValue), coloured by the TSL key of each phase's Laue group (orix). Not indexed points are black."
        case .phase: "Each point in its phase's colour, as orix's phase list gives it; not indexed points are white."
        case .property(let name): "The file's \(name) at every point, through the Display section's colormap."
        case .derived(let d): MapsRoomFormat.derivedNote(d, load: appState.maps.loadDirection)
        }
    }
}

/// Display: a scalar layer's colormap, window and gamma (the Image room's rows), and the picked point's inset on the map (#1064).
struct MapsDisplaySection: View {
    let session: OrientationMapSession
    @Bindable var state: MapsRoomState

    var body: some View {
        InspectorSection("Display") {
            if !session.layer.isColour {
                ImageRoomDisplayRows(presentation: session.propertyPresentation, colormapID: "maps.colormap")
            }
            InspectorRow("Pattern inset") {
                Toggle("Pattern inset", isOn: $state.showsPointInset)
                    .toggleStyle(.switch).labelsHidden()
                    .help("The picked point's pattern, or its unit cell for a map without patterns, in the map's top-right corner")
                    .accessibilityIdentifier("maps.showInset")
            }
        }
    }
}

/// Export (closed until opened, as the other rooms'): the map with its colour key, phase legend or range, and a scale bar.
struct MapsExportSection: View {
    @Environment(AppState.self) private var appState
    let session: OrientationMapSession
    let state: MapsRoomState

    var body: some View {
        InspectorSection("Export", startsExpanded: false) {
            InspectorActionRow {
                Button("Map PNG…") {
                    Task { await state.exportMap(from: session, directory: appState.exportDirectory, report: { appState.statusText = $0 }) }
                }
                .disabled(session.raster == nil)
                .help("The map on screen as a PNG figure: whole pixels per point, a scale bar, and the colour key or phase legend beside it")
                .accessibilityIdentifier("maps.export.map")
            }
            InspectorActionRow {
                Button("Map PDF…") {
                    Task { await state.exportMap(from: session, format: .pdf, directory: appState.exportDirectory, report: { appState.statusText = $0 }) }
                }
                .disabled(session.raster == nil)
                .help("The map on screen as a 90 mm vector figure: the map, its boundaries as lines, a scale bar and the key below, with live text")
                .accessibilityIdentifier("maps.export.mapPDF")
            }
            InspectorActionRow {
                Button("Map SVG…") {
                    Task { await state.exportMap(from: session, format: .svg, directory: appState.exportDirectory, report: { appState.statusText = $0 }) }
                }
                .disabled(session.raster == nil)
                .help("The same vector figure as SVG, for Illustrator or Inkscape")
                .accessibilityIdentifier("maps.export.mapSVG")
            }
            InspectorActionRow {
                Button("Grains CSV…") {
                    Task { await state.exportGrains(from: session, directory: appState.exportDirectory, report: { appState.statusText = $0 }) }
                }
                .disabled(session.analysis == nil)
                .help("The grain table as CSV: size, equivalent diameter, mean orientation, GOS, neighbours and the largest Schmid factor of each grain")
                .accessibilityIdentifier("maps.export.grains")
            }
            InspectorActionRow {
                Button("Histogram CSV…") {
                    Task { await state.exportHistogram(from: session, directory: appState.exportDirectory, report: { appState.statusText = $0 }) }
                }
                .disabled(session.analysis == nil)
                .help("The Histogram tab's distribution (KAM, GOS or grain size) as CSV: each bin's edges and count")
                .accessibilityIdentifier("maps.export.histogram")
            }
            InspectorActionRow {
                Button("Texture PNG…") {
                    Task { await state.exportTexture(from: session, directory: appState.exportDirectory, report: { appState.statusText = $0 }) }
                }
                .disabled(session.texture == nil)
                .help("The pole figures, the IPF-Z density and the ODF sections of the texture phase as one figure, each with its colour bar")
                .accessibilityIdentifier("maps.export.texture")
            }
        }
    }
}

struct MapsRoomInfo: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let document = appState.maps.document {
            InspectorSection("Map") {
                ForEach(MapsRoomFormat.infoRows(document)) { row in
                    InspectorValueRow(row.label, row.value)
                }
                InspectorNote(MapsRoomFormat.sourceNote(document.source))
            }
        } else {
            ContentUnavailableView("No orientation map open", systemImage: "map",
                                   description: Text("The map, its phases and how its colours are made appear here."))
        }
    }
}
