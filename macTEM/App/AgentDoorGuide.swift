//
//  AgentDoorGuide.swift
//  Role: the agent door's workflow guide (#558, as mac4DSTEM#236): how a person works through a file in macEM's rooms and the checks
//        they make at each step, so an agent does not bring its own idea of what "good" looks like. It grows with the rooms the door
//        reaches; a room without its tools is named as the person's for now.
//
//        The guide names methods, not numbers for one dataset: no value here is tuned to a sample. Every tool it names in backticks is
//        a registered tool (`AgentDoorGuideTests`), so it cannot send an agent to a tool that is gone.
//

import Foundation
import ShellAgentDoor

extension MacTEMAgentDoor {
    static let guideTools: [AgentTool] = [
        AgentTool(name: "get_workflow_guide", title: "Workflow guide",
                  summary: "Read this first. How a person works through a file in \(AppName.display), room by room, which tool does each "
                      + "step and how to judge the result. topic: " + Guide.allCases.map(\.rawValue).joined(separator: ", ")
                      + "; overview by default.",
                  input: .noWindow,
                  parameters: [AgentParameter("topic", .choice(Guide.allCases.map(\.rawValue)), summary: "The part to read.")]) { call in
            let topic = call.arguments["topic"].flatMap(Guide.init(rawValue:)) ?? .overview
            return .json(["topic": topic.rawValue, "guide": topic.text,
                          "other_topics": Guide.allCases.filter { $0 != topic }.map(\.rawValue)])
        },
    ]

    /// The guide's parts, as `get_workflow_guide` hands them out.
    nonisolated enum Guide: String, CaseIterable {
        case overview
        case eds

        var text: String {
            switch self {
            case .overview: Self.overviewText
            case .eds: Self.edsText
            }
        }

        private static let overviewText = """
            How a person works in \(AppName.display). A window (a tab is a window) holds open files and shows one room at a time: \
            Image, FFT, EDS, EELS, Diffraction, Patterns, Indexing, Maps and Results. A file opens in the room that fits it: an image \
            in Image, a diffraction pattern in Diffraction, an EDS spectrum image or spectrum in EDS, an EELS spectrum image in EELS, \
            an EBSD pattern scan in Patterns, an orientation map in Maps.

            1. Look. `list_windows` names the windows; `get_window` says the room, the open files with their size, calibration and \
            voltage, the status line and any error. `get_image` draws the shown image as Export Image… draws it; `get_results` gives \
            the finished numbers as Export Results… writes them; `get_log` gives the Output lines.
            2. Open. The person opens their own files (File > Open). `open_demo` opens one of the shipped demo documents in its room, \
            as Help > Open Demo Data does, for trying a room.
            3. Move. `select_room` moves the window to a room, as the room bar does; a room the window's files do not fill is refused \
            with the reason the room bar gives.
            4. Work the room. Topic eds for the EDS room. The other rooms' controls are the person's for now: look at their result \
            with the get tools and ask the person to set and run them.

            Ways of working the person expects:
            - Read the app's own signals after every step and act on them before the next one: a refusal, a fit failure, a flag, \
            a status line. Never build a step on a flagged result.
            - Change one setting at a time and look at the result after each change. The pictures are drawn by the code that draws \
            the person's screen and exports, so judge them as the person would.
            - Every change shows in the person's Output as "An agent …" (`get_log`).
            - Do not run anything long until the person says so.
            - Say what you saw, and mark a reading as yours unless the data proves it (for example "fits an Mg-Si phase").
            - When a tool refuses, its message says why and what would make it possible; do that or ask the person.
            - A tool that starts work answers at once; wait until the room's own get tool says not busy, then read the result or \
            the reason it failed.
            - Numbers in the JSON fields use a point. The status and Output lines are the window's own text, written in the Mac's \
            Region (a German Mac writes "6,5 nm"): read numbers from the JSON, not from those lines.
            """

        private static let edsText = """
            EDS room (energy-dispersive X-ray spectra: a TEM or SEM spectrum image, or one spectrum). The room is shared with \
            4DSTEM Studio, and so are its tools.

            1. `select_room` room edx, then `get_eds`: the file, the picked elements and their roles, the region, the kept regions, \
            each line window's net counts with σ, and Auto ID's suggestions.
            2. Elements. `run_eds` action auto_id finds the elements in the region's spectrum, as Auto ID does; it suggests near \
            misses and never adds one by itself. `set_eds` add and remove pick elements by symbol. An element whose line overlaps \
            a quantified one but is not wanted in the composition is set fit only (fit_only); the rest are quantified.
            3. Region. `set_eds` region whole sums the whole map; rectangle or ellipse (x0, y0, x1, y1 in scan pixels, ends \
            exclusive) draws one as on the map and keeps it as a numbered region; pin picks a kept region by name.
            4. Quantify. `run_eds` action quantify fits the picked lines and quantifies them, as Quantify does; from then on the \
            fit follows every change. Wait until `get_eds` says not busy; it then holds the table: \
            k-factors, wt% and at% with their uncertainties, or why the fit failed.
            5. Look. `get_eds_maps` draws the shown element maps as Maps as PNG… does, with the kept regions and the scale bar.

            What to check:
            - Every strong peak is explained by a picked element (Auto ID's list and the net counts say which are not). Escape and \
            sum peaks, the grid (often Cu or Ni) and the holder are not the sample: ask the person before quantifying them.
            - A net count whose σ is as large as the count is not a detection.
            - A wt% with an uncertainty as large as itself is not a measurement.
            - A region on the matrix and one on a feature, compared, say more than the whole map.
            """
    }
}
