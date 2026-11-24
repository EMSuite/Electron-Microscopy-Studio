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
import TEMCore

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
        case patterns
        case indexing
        case maps
        case eels
        case image
        case fft
        case diffraction

        var text: String {
            switch self {
            case .overview: Self.overviewText
            case .eds: Self.edsText
            case .patterns: Self.patternsText
            case .indexing: Self.indexingText
            case .maps: Self.mapsText
            case .eels: Self.eelsText
            case .image: Self.imageText
            case .fft: Self.fftText
            case .diffraction: Self.diffractionText
            }
        }

        private static let overviewText = """
            How a person works in \(AppName.display). A window (a tab is a window) holds open files and shows one room at a time: \
            Image, FFT, EDS, EELS, Diffraction, Patterns, Indexing, Maps and Results. A file opens in the room that fits it: an image \
            in Image, a diffraction pattern in Diffraction, an EDS spectrum image or spectrum in EDS, an EELS spectrum image in EELS, \
            an EBSD pattern scan in Patterns, an orientation map in Maps.

            1. Look. `list_windows` names the windows; `get_window` says the room, the open files with their size, calibration and \
            voltage, the status line and any error. `get_image` draws the shown image as Export Image… draws it; `get_results` gives \
            the finished numbers as Export Results… writes them; `get_session` gives the SEM session's rows as the Results room's \
            session table lists them; `get_methods_record` gives the room's methods record and paragraph as Export Methods Record… and \
            Copy Methods Paragraph give them; `get_log` gives the Output lines.
            2. Open. `list_agent_folder` lists the Agent folder the person chose in Settings > Agents; `open_file` opens one of its \
            files as File > Open does, in the room that fits it. Files elsewhere stay the person's to open. `open_demo` opens one of \
            the shipped demo documents in its room, as Help > Open Demo Data does, for trying a room.
            3. Move. `select_room` moves the window to a room, as the room bar does; a room the window's files do not fill is refused \
            with the reason the room bar gives.
            4. Work the room. Topic eds for the EDS room, patterns for the EBSD Patterns room, indexing for the Indexing room, maps \
            for the Maps room, eels for the EELS room, image for the Image room (marks and particles), fft for the FFT room, diffraction for the Diffraction room. The other rooms' controls are the person's for now: look at their result with the get tools and ask the person to set and \
            run them.
            5. Run. `run_room` presses the shown room's toolbar verb (Quantify, Run, Process, Index, Segment), as ⌘R does; it is \
            refused with the button's own words while it cannot run. `stop_run` stops what runs, as ⌘. does.

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

        private static let patternsText = """
            Patterns room (EBSD and TKD pattern scans; kikuchipy's processing). The scan map is on the left, the pattern at the \
            picked position on the right. The file stays unchanged: processing runs in memory.

            1. `get_patterns`: the scan and pattern size, the file's calibration (detector, projection centre), the picked \
            position, the map, and every processing setting with each stage's state. Wait until busy is false: the open runs a \
            pass over the scan for the maps.
            2. Look. `get_patterns_picture` which map draws the scan map, which pattern the pattern. The mean intensity map shows \
            the grains and the scan's edges; `set_patterns` map image_quality or dot_product draws the quality maps (Krieger Lassen's \
            image quality, the average dot product with the four neighbours), where grain boundaries and bad points are dark. \
            `select_scan_position` picks a position (x the column, y the row): look at a grain's middle, a boundary, a dark point.
            3. Virtual images. `set_patterns` grid 5 cuts the detector into 5 × 5 tiles (kikuchipy's default); map tile with tile \
            r2 c1 shows one tile's image, and mix_red, mix_green, mix_blue make the colour mix, which shows orientation contrast \
            before any indexing.
            4. Process. `set_pattern_processing` sets the stages; `set_patterns` display processed shows the pattern through them. \
            The room's default is kikuchipy's: the file's static background subtracted, then the dynamic background (a Gaussian \
            blur of width / 8) subtracted. `run_room` (Process) runs them over the whole scan; NLPAR and neighbour averaging show \
            only after that, since they need the neighbours.
            5. Simulation. For a file that stores orientations, `set_patterns` simulation geometrical draws the Kikuchi bands and \
            zone axes of the orientation stored at the shown point over its pattern (kinematical adds the simulated pattern under \
            them); `get_patterns` simulation says what is drawn or why nothing is. Bands that sit on the pattern's bands say the \
            stored orientation and projection centre fit this point.

            What to check:
            - After the backgrounds the bands stand out evenly over the whole pattern, with no bright centre or dark corners left. \
            A pattern that is mostly noise after the dynamic background had too small a blur (raise dynamic_std).
            - The static background needs one from the file or the scan's mean (static_source mean); get_patterns says when the \
            file has none (processing_refusal).
            - Binning trades pattern detail for speed: index at the size the bands still read.
            - NLPAR's λ is chosen from the scan's noise (nlpar_lambda after Process); compare a processed pattern with and without it.
            - Processing changes no orientation by itself: judge it on the patterns, then index (the Indexing room).
            """

        private static let indexingText = """
            Indexing room (EBSD and TKD orientations from the Patterns room's scan: pyEBSDindex's Hough indexing or kikuchipy's \
            dictionary indexing). It indexes the patterns as the Patterns room processes them; the processing is set there.

            1. `select_room` room indexing, then `get_indexing`: where the patterns come from, the projection centre, the phases, \
            the method and its settings, and index_refusal, which says what Index still needs.
            2. Phases. The file's own phases come first. `set_indexing_phase` add puts a built-in phase in the list; phase with on \
            picks those indexed against. Hough matches bands to a reflector list (fcc, bcc, hcp) that must fit the phase's \
            structure. Index against the phases the person expects in the sample, no more: each extra phase is a chance for a \
            wrong match.
            3. Method. `set_indexing` method hough is fast and needs no master pattern; dictionary compares every pattern with \
            patterns simulated from a master pattern (the shipped Ni one, or one the person opens) and is slower and more robust \
            on noisy patterns. Their settings start at kikuchipy's tutorial values; change one at a time.
            4. Index. `run_room` presses Index. Wait until `get_indexing` says not busy; run then holds the state, the points \
            indexed per phase, the mean confidence index or score and, for Hough, the mean fit.
            5. Look. `get_indexing_picture` which map draws the layer on screen (`set_indexing` layer: IPF-Z, X, Y, Euler, phase, \
            or a quality layer). `select_scan_position` picks a point: get_indexing then gives its solution and detected bands, \
            and which pattern and best_match draw its pattern and a Dictionary run's best match.
            6. Check and hand on. `set_indexing` compare with compare_a and compare_b compares two results point by point (the \
            median disorientation and the share over 2°). `open_in_maps` sends the run to the Maps room for grains and texture.

            What to check:
            - The IPF map shows grains of one colour each with sharp boundaries. Speckle inside a grain, or one colour over the \
            whole scan, is a wrong match: check the phases, the reflectors and the patterns' processing before changing anything \
            else.
            - Confidence index (Hough) or score (Dictionary): low values sit at grain boundaries and on bad patterns; low values \
            inside grains say the indexing is not reliable there. For Hough, a fit (the bands' mean angular misfit) that rises \
            inside grains says the same.
            - Points not indexed, and how many matched bands the picked points have: a pattern with few matched bands has a \
            doubtful solution.
            - The detected bands lie on the pattern's bands; bands found on noise mean the patterns need processing first.
            - A Hough and a Dictionary run that agree (a small median disorientation in Compare) support each other; where they \
            disagree, look at those points' patterns.
            - A refinement (refine) is judged by its mean score as indexed and as refined, and by its projection centre's spread.
            """

        private static let mapsText = """
            Maps room (orientation maps: an .ang, .ctf, .h5oina or orix .h5 file, a pattern file's own map, or the Indexing room's \
            run through `open_in_maps`; orix's colours and DefDAP's grain analysis).

            1. `get_maps`: the map and where it came from (a run the Indexing room has moved on from says so in source_stale), the \
            phases with their points, the points not indexed, the layer and the layers on offer.
            2. Look. `get_maps_picture` which map draws the layer with its colour key: `set_maps` layer ipf-x, ipf-y or ipf-z shows \
            the crystal direction along that sample axis, phase the phases, property-<name> a column of the file (image quality, \
            confidence index, fit). `select_scan_position` picks a point; get_maps then gives its phase and Bunge angles.
            3. Segment. `set_maps` boundary_angle, minimum_size and kam_max are DefDAP's (5°, 10 points, 5° by default); \
            `run_room` presses Segment. Wait until not busy; get_maps then holds the number of grains, their mean size and the ASTM \
            grain size number, and the derived layers (derived-kam, derived-gos, derived-grains, derived-gnd) are on offer.
            4. Grains. `get_grains` lists the grain table (sort size for the largest first) and, with histogram, the KAM, GOS or \
            grain size distribution. `select_grains` selects grains as the table does.
            5. Slip. `set_maps` load picks the load axis and slip_systems with slip_phase the phase's slip-system file; the derived \
            Schmid layer and each grain's largest Schmid factor follow.
            6. Texture. `set_maps` texture_phase computes a phase's pole figures, IPF density and ODF sections (orix's); \
            `get_maps_picture` which texture draws them, and get_maps gives each figure's maximum in multiples of random.

            What to check:
            - Points not indexed: many, or a band of them, say the map is of limited use there; say so before analysing it.
            - A phase map with isolated single points of another phase is usually misindexing, not a second phase; ask the person.
            - The boundary angle decides what a grain is: 5° (DefDAP) is low-angle sensitive, 15° counts only high-angle \
            boundaries. State the angle with every grain count or size.
            - Grains of only a few points are noise; the minimum size removes them. Report the minimum size with the counts.
            - KAM and GOS rise with deformation and with noise: compare a region you expect to be undeformed before reading them \
            as strain.
            - A texture from few grains is not a texture: state the points and grains it rests on.
            """

        private static let eelsText = """
            EELS room (electron energy-loss spectrum images: a low loss and a core loss, or one of them; exSpy's methods through \
            SpectroKit). Run runs the stages that are not current in order: align the zero-loss peak, map the thickness (t/λ), \
            deconvolve, fit the picked edges.

            1. `select_room` room eels, then `get_eels`: which spectra the file holds, E₀, α and β with where each comes from, each \
            stage's state, every setting, and the edges the core loss offers.
            2. Microscope. The fit's cross-sections need E₀, α and β. Where the file lacks one, fitting.blocker says so; ask the \
            person for the value before typing it with `set_eels`, never guess it.
            3. Thickness. `run_room` presses Run. The maps (`get_eels_maps`; `set_eels` maps picks ZLP, t/λ, t, at% or wt%) and \
            the thickness line say t/λ; t needs a mean free path (`set_eels` mfp given with lambda_nm, or estimate with a density).
            4. Edges. `set_eels_edges` add picks each element's default edge, as a click on the periodic table does; edges_add a \
            single edge by id. Pick only edges seen in the spectrum (`get_eels_spectrum`). fit_only keeps an element in the fit and \
            out of the composition (an overlapping edge that is not wanted).
            5. Fit. `run_room` again fits the edges. `get_eels` then holds each edge's intensity, areal density, at% and wt% with σ, \
            the background exponent, and the fit's reduced χ².
            6. Regions. `set_eels_region` rectangle or ellipse fits a region of the map; whole goes back to the whole map. A region \
            on a feature beside one on the matrix says more than the whole map.

            What to check:
            - t/λ above about 1 means strong plural scattering: say so beside any composition; deconvolution (fourierRatio) or \
            convolve in the fit accounts for it.
            - An edge whose background exponent sits at its bound (exponent_at_bound), or whose window refusal is set, is not \
            measured: look at the spectrum around it before reporting it.
            - A reduced χ² far above 1 says the model misses part of the spectrum (an unpicked edge, fine structure, a wrong \
            window).
            - An at% with a σ as large as itself is not a measurement.
            - Changing a setting makes the stage stale: run again before reading the numbers.
            """
        private static let imageText = """
            Image room (an image: TEM, STEM, SEM; ImagoKit's measurements). The marks measure distances, angles and line profiles \
            in the file's calibration; Particles finds bright or dark objects by a threshold and counts them.

            1. `select_room` room image, then `get_image_room`: the size and calibration (a length in nm needs a calibrated file; \
            an uncalibrated one measures in pixels), a stack's frame, the marks, an SEM file's rows, and the Particles settings.
            2. Look. `get_image` draws the picture with its marks and scale bar. Find what to measure on it before measuring.
            3. Marks. `set_marks` add distance, angle or profile with points in image pixels (x right, y down, a pixel's centre at \
            whole numbers). Each mark's value is the Measure section's text. `get_profile` gives a profile's samples; width averages \
            across the line. A lattice spacing is better measured over several periods and divided.
            4. Particles. `set_particles` polarity bright or dark, then a threshold (manual, in the image's raw intensity, inside \
            raw_range) or method otsu, sigma to smooth noise, minimum_area to drop specks, region to leave out a scale bar or a \
            label. show true finds the objects; `get_image_room` then holds the counts, sizes and areal density, and `get_particles` \
            the object table or its CSV. tint_mask shows the object side of the threshold on `get_image` while settings change.
            5. Stacks. `set_image_room` frame or step moves through a stack's frames; hold_contrast keeps one contrast window so a \
            change of brightness between frames shows.

            What to check:
            - Look at the outlines on `get_image` after Show Objects: an object that is two touching particles, or noise counted as \
            objects, says the threshold, sigma or minimum area is off.
            - Edge objects are not counted (they are cut); the areal density is edge-corrected. Report counted and edge together.
            - A render (a screen capture) has burnt-in labels and a scale bar that are found as objects: render_note says so; draw \
            a region that leaves them out.
            - A result is stale (current false) once a setting changed: show again before reading it.
            - A mark's length in pixels on an uncalibrated image is not a length: say so.
            """
        private static let fftText = """
            FFT room (the power spectrum of an image or a square region of it; ImagoKit's FFT, spot estimator, masked inverse \
            and D. R. G. Mitchell's HRTEM filters). Spots on the transform give lattice spacings d and the angles between them.

            1. `select_room` room fft, then `get_fft`: the region transformed, Δq and the Nyquist frequency, and whether the \
            transform is current (it is computed after each change; ask again while computing is true).
            2. Region. `set_fft` region "x y size" transforms an even square of at least 32 px; centred takes the largest centred \
            square; whole the whole image. A region on one grain or one crystal gives sharp spots; one across a boundary mixes \
            two lattices. A taper (hann, the Window menu) removes the cross a hard edge draws.
            3. Look. `get_fft_picture` transform draws the spectrum with a ring and number per measured spot.
            4. Spots. `set_fft_spots` find true finds the strongest reflections and measures each; measure_at "kx ky" measures \
            one bin from the centre, as a click does. `get_fft` lists each spot's d, |q| and its angle to the first spot; \
            `get_fft_data` spots gives them as Spots CSV… writes them.
            5. Masked inverse. With spots in the mask, `set_fft` view maskedInverse shows the image made of those frequencies; \
            mask_radius and mask_edge shape the mask. `get_fft_picture` source draws it.
            6. HRTEM filters. `set_fft` filter true runs ABSF and Wiener on the region (an even square); view absf or wiener \
            shows each.

            What to check:
            - A spot flagged neighbour has another peak within 3 bins: its d may be off by up to 0.3 %. Say so.
            - The accuracy note says how precise d is for the region's size; a small region gives coarse d.
            - Spots that are pairs through the centre (kx, ky and −kx, −ky) are one reflection: report it once.
            - A d is a lattice spacing only on a calibrated image; on pixels it is a length in pixels.
            - The filtered images are pictures, not measurements: intensities are not preserved.
            """
        private static let diffractionText = """
            Diffraction room (a selected-area or nanobeam diffraction pattern; DiffractoKit's ring fit, calibration and kinematic \
            indexing). A ring fitted on a known standard sets the scale; rings and spots are then indexed against a crystal.

            1. `select_room` room diffraction, then `get_diffraction`: the centre and its source, the scale in use (a ring fit, \
            the file's axis or a typed Δq), the beam energy, the standard and its families (each with its index), the crystal, \
            and every ring and spot with its readout.
            2. Centre. It starts at the image centre. `set_diffraction` centre_row and centre_column type one; after a ring fit, \
            use_ring_centre takes that ring's fitted centre. A wrong centre biases every radius: fit a ring and take its centre first.
            3. Calibrate. `set_diffraction` inner and outer set an annulus that holds one ring of the standard; family picks that \
            ring (its index in families) and calibrate true fits it and sets Δq, the wavelength and the camera length from it. \
            The fit answers at once: ask `get_diffraction` until fitting is false. A file without a reciprocal axis needs this or \
            delta_q; a file without a voltage needs beam_kv for the camera length. camera or pixel_pitch gives L in mm.
            4. Measure. fit_ring true fits another ring in a new annulus; `set_diffraction_marks` add_spot "row column" adds a \
            spot as a click does (its centre refined on the pattern). Each row says radius, q, d, the family indexed, the listed \
            d and the deviation in %.
            5. Index. crystal picks the crystal the rows are indexed against; k_max and tolerance (% of q) set the list and the \
            match. Rows are indexed again at once, with no refit. `get_diffraction` csv true gives Export Readout CSV…'s text.

            What to check:
            - fit_versus_file_percent compares the ring's Δq with the file's axis: a few % says the file's camera length is off; \
            report the fitted scale.
            - A ring with a refusal has no radius: move the annulus so it holds the whole ring and nothing else.
            - A verdict other than accepted is not an index: report it in the verdict's own words.
            - Calibrating on a ring indexes that ring by construction: it does not test the scale. A second ring or spot does.
            """
    }
}
