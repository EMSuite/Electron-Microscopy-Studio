# The agent door

A local API through which an agent on the same Mac (Claude, Codex, a script) looks at what Electron Microscopy Studio's
windows show and, behind a second switch, works a room. The app is the MCP server itself, over HTTP at
`http://127.0.0.1:47812/mcp`; nothing is installed beside it. The door itself (listener, token, Settings section, window
list, MCP endpoint) is EMSuiteUI's `ShellAgentDoor` (EMSuiteUI `docs/agent-door.md`), shared with 4DSTEM Studio, whose
door this one follows (4DSTEM Studio `docs/agent-door.md`). This app hands the door its tools.

## Turning it on

1. Settings > Agents > "Let agents on this Mac look at open windows". Off by default.
2. Copy Connection Command, and paste it into Terminal once (Claude Code), or into the Claude desktop extension
   `macEM.mcpb`; Codex takes the address and token in `~/.codex/config.toml` (EMSuiteUI `docs/agent-door.md`).
3. For the tools that act, also "Let agents run analyses". The agent's client asks the person before each such call.

## Tools that look

| Tool | Answer |
|---|---|
| `get_workflow_guide` | how a person works through a file here and how to judge each step (topics `overview`, `eds`, `patterns`, `indexing`, `maps`, `eels`, `image`, `fft`, `diffraction`); read first |
| `list_windows` | the open windows (`w1`, `w2`, ...), each with its shown file, room and number of open files (the door's own tool) |
| `get_window` | the room, the open files (size, calibration, voltage once read), the shown file's number of results, the status line, any error; whether an open runs, the rooms with work in flight, the one-document rooms' files, the app's memory footprint now and at its peak (the size table, #904) |
| `get_image` | the shown image as Export Figure… draws its PNG (display window, colormap, scale bar, marks), longest side up to 1024 px per `scale` step |
| `get_results` | the shown file's finished measurements as Export Results… writes them (CSV) |
| `get_log` | the window's Output lines |
| `list_agent_folder` | the files of the Agent folder the person chose in Settings > Agents, as `open_file` takes them |
| `get_session` | the Results room's SEM session table: every SEM result with its group, value, source, time, Info fields, methods and logged lines, and an SEM spectrum's conditions (with the take-off angle) |
| `get_methods_record` | the room on screen's methods record as Export Methods Record… writes it (JSON) and the paragraph Copy Methods Paragraph copies; `leave_out_file_names` names each source "source 1", ... (every room; the first ask in an SEM room or the EDS room may be refused while its file is read for its fingerprint: ask again) |
| `get_eds` | the EDS room: file, picked elements and roles, region, kept regions, line windows' net counts with σ, Auto ID's suggestions, the results table or why the fit failed |
| `get_eds_maps` | the EDS maps as the room's Maps as PNG… draws them |
| `get_patterns` | the Patterns room: scan and pattern size, the file's calibration, the picked position, the map and grid, the colour mix, every processing setting (in `set_pattern_processing`'s names) with each stage's state, why Process is refused, NLPAR's λ, what is running, and the Kikuchi simulation overlay (its mode and settings, what it draws or why it draws nothing) |
| `get_patterns_picture` | `which` map or pattern: the Patterns room's pane as its Export section draws it (Map PNG…, Pattern PNG…); a small one is enlarged by a whole factor, no smoothing |
| `get_indexing` | the Indexing room: where its patterns come from, the phases, the method and every Hough, Dictionary and Refine setting (in `set_indexing`'s names), the master patterns open, why Index is refused, the run on screen (state, points indexed per phase, mean confidence or score and fit), the picked point's solution and detected bands, Compare's summary, what is running |
| `get_eels` | the EELS room: the file's spectra, E₀, α, β and their sources, each stage's state, every Processing and Fitting setting (in `set_eels`' names), the picked and offered edges, the edge results with σ and the fit's reduced χ², the regions and their rows, the notices and refusals |
| `get_eels_spectrum` | the selected region's spectrum as Spectrum CSV… writes it, and the regions' rows as Regions CSV… writes them |
| `get_eels_maps` | the EELS maps the Maps control picks, as Maps… draws them |
| `get_maps` | the Maps room: the map and its source (stale when the Indexing room moved on), phases, points not indexed, the layer and the layers on offer, the picked point's phase, Bunge angles, grain and KAM, Segment's settings and summary, the selected grains, Slip and Texture |
| `get_grains` | after Segment: the grain table (a page of it, by number or largest first) and, with `histogram`, the KAM, GOS or grain size bins as the Histogram tab draws them |
| `get_maps_picture` | `which` map (Export's Map PNG…: the layer with its key or legend, the scale bar, the boundaries when shown) or texture (Texture PNG…) |
| `get_image_room` | the Image room for the shown file: size and calibration, a stack's frame, the measuring tool, the marks (numbered, their points and their values as the Measure section words them), an SEM file's rows and vendor fields, the Particles settings, region and raw range, and the last Show Objects' counts, sizes and areal density |
| `get_particles` | after Show Objects: the object table (a page, by number or largest first, counted only as the table's switch) or Export CSV…'s text |
| `get_profile` | a profile mark's samples as Export Profile… writes them |
| `get_fft` | the FFT room for the shown file: the region transformed, smoothing and band-pass applied first, the taper (the Window menu), Δq and the Nyquist frequency, the spots (bin, d, \|q\|, angle to the first, neighbour flag, in the mask, or why not measured), the finder's settings, the masked inverse, the HRTEM filters' parameters and last run, the strain maps (GPA: the spots taken as g₁ and g₂, the reference, each map's drawn range (the 99th percentile of its magnitudes; rotation clockwise positive), the validation note), the source pane's view, what is computing |
| `get_fft_data` | `which` radial_profile or spots, as Radial profile CSV… and Spots CSV… write them |
| `get_fft_picture` | `which` transform (Transform PNG…: the spectrum in its Display window, reciprocal scale bar, a ring per measured spot) or source (what the source pane shows) |
| `get_diffraction` | the Diffraction room for the shown pattern: the centre and its source, the scale in use (a ring fit on a standard, the file's axis or a typed Δq) with the wavelength and camera length a fit gives, the beam energy and camera, the standard and its families, the crystal with its lattice and library phase id, k_max and the tolerance, the annulus and tool, every ring and spot, and the readout (radius, q, d, family, listed d, deviation, verdict); with `csv`, the Export section's Readout CSV… text |
| `get_spot_table` | Index's answer for the shown pattern: indexing, the verdict and its line as the header writes it, the solutions (zone axis, degrees off it, orix quaternion), the score, the fitted scale, the misfit, the spots explained, zone axis only, scale or spots changed since; the Spots table's rows (spot, hkl, R px, q, d, d expected, Δd/d %, phase) and every spot marked, found or clicked; with `csv`, the Export section's Spots CSV… text |
| `get_diffraction_picture` | the pattern as the Diffraction room shows it, with the marked spots (yellow, numbered as the Spots table) and the simulated spots (cyan, the strongest labelled with hkl) |
| `list_phases` | the phase library on this Mac: each phase's id, name, source and credit, marker, lattice and whether it was edited, its free lattice parameters, unreadable records, and an `add_phase` running or its outcome |
| `read_simulation` | the shown Simulation document or its HRTEM image: phase, zone axis, the specimen's summary or refusal (with the strain Build with Strain would accept), the optics, defocus and stored thicknesses, the potential and transfer (point resolution, aperture cut-off, Scherzer defocus), the method line, frozen phonons (σ, configurations, the plan line or why it does not fit, the run's progress, the convergence and where it was read), the atom columns ringed on the image (their count and the first 50 in its pixels with their elements), Place Beside and its readout, whether a run is going or the waves are stale, and the sections' failure sentences |
| `read_dynamical` | the Simulation section's Intensities: Kinematic or Dynamical, the stored thicknesses and the one shown, the method line, why the kinematical spots are drawn instead, the beams with their intensity, and Index's spot rows with theirs |
| `read_cbed` | the Beam and CBED rows: the settings, the semiangle used and the largest that keeps the discs apart, the overlap sentence, the plan and small-box warning, why Show CBED Pattern cannot run, the run's progress and failure, the stored patterns, the depth chip and the method line |
| `read_thickness` | the Thickness section for the pattern shown: the verdict and sentence, the thickness, extinction distances and residual, the fringe line, the method line, the profile with the fitted curve and the minima, and whether Use in Simulation is offered |
| `read_stem` | the STEM section: the settings with the defocus and step used, the plan line, the wrap and band warnings, why Simulate cannot run, the run's progress and positions, whether the settings changed since, the detector band, the scattered intensity against angle, the "not quantitative" chip and the method line |
| `get_indexing_picture` | `which` map (the layer as Export's Map PNG… draws it), pattern (as indexed, without the band overlay) or best_match (a Dictionary run's) |
| `get_crystal_view` | the Diffraction room's crystal pane: shown or hidden, the phase, the zone axis nearest the drawn orientation and the tilt off it, the orientation as the 3 by 3 matrix the simulated spots are drawn with, the unit cell switch and the scene (atoms and bonds by element, cell lengths); with `picture`, the pane's picture (the first ask starts the drawing and answers 409, ask again) |

Every picture and number comes from the code that draws or exports it for the person, so the agent judges what the
person sees. Numbers in JSON fields use a point; the status and Output lines are the window's own text, in the Mac's Region.

## Tools that act

Behind "Let agents run analyses". Each goes through the entry point its control uses and leaves an Output line that starts
"An agent", so the person can tell the agent's steps from their own.

| Tool | Does |
|---|---|
| `select_room` | moves the window to a room, as the room bar does; a room the files do not fill is refused with the room bar's reason |
| `open_demo` | opens a demo document in its room, as Help > Open Demo Data does |
| `open_file` | opens a file of the Agent folder (Settings > Agents) as File > Open does, in the room that fits it; paths outside the folder are refused; `room` (eds or eels) answers the question File > Open asks for TIA spectra no `.emi` places, and such spectra are refused without it |
| `set_eds` | picks and removes elements, sets an element's role (quantify or fit only), chooses the region (whole, rectangle, ellipse, polygon, a kept region), keeps the selected region as Pin Region does, and draws a line profile as the Line tool does |
| `run_eds` | Auto ID, Quantify or Stop; answers at once, `get_eds` says busy until done |
| `run_room` | presses the shown room's toolbar verb, as ⌘R does (Quantify, Run, Process, Index, Segment); refused with the button's own words while it cannot run |
| `stop_run` | Stop, as ⌘. does: the shown room's run or open, or a run left going in another room |
| `select_scan_position` | picks a scan position (x column, y row) as a click on the Patterns, Indexing or Maps room's map does; in the Indexing room the pattern pane shows it as indexed, in the Maps room the grain under it is selected |
| `set_patterns` | the Virtual images section (grid, map, tile, colour mix, tiles pane), the pattern's Raw/Processed switch and the Simulation section (overlay, Min d, Band width, Zone axes, Labels, Blend); says when a new grid also dropped the tile map or the mix |
| `set_pattern_processing` | the Processing sections' settings (static and dynamic background, intensity, FFT filter, binning, neighbour averaging, NLPAR), only those given |
| `set_indexing` | the Indexing room's Display (layer, detected bands, simulation, Compare A and B), Method, Hough, Dictionary and Refine settings, only those given; `reset` goes back to a section's defaults first |
| `set_indexing_phase` | adds a built-in phase; turns a phase on or off, sets its reflector list or its master pattern, or removes it |
| `open_in_maps` | Open in Maps: the run on screen goes to the Maps room |
| `set_maps` | the Maps room's source, layer, Segment settings (boundary angle, minimum size, KAM maximum), boundaries, load axis and slip systems, texture phase, and the bottom pane's tab and histogram |
| `set_eels` | the EELS room's Processing (alignment, threshold, deconvolution, mean free path; `align` runs Align alone), Fitting (model, fit end, background, convolution, E₀, α, β) and Maps (segment, display filter) settings |
| `set_eels_edges` | the periodic table: adds an element's default edge, removes an element, picks single edges, fit only or quantify, resets the windows, MLLS references |
| `set_eels_region` | the EELS region: whole map, a rectangle or ellipse, a kept region by name, or removes one |
| `set_image_room` | the Measure section's tool, and a stack's frame, step and Same contrast for every frame |
| `set_marks` | adds a distance, angle or profile mark from points in image pixels as a drag does, selects a mark, removes marks, sets the selected profile's width |
| `set_particles` | the Particles section's settings (bright or dark, manual level or Otsu, smoothing, connectivity, minimum area, region, mask tint), Show Objects, Hide, and the object selected |
| `set_fft` | the FFT room's Region (a square, centred, whole), taper (the Window menu), smoothing and band-pass, the source pane's view, the mask's radius and edge, the spot finder's settings, the HRTEM filters' parameters, and Filter, the strain reference and Map Strain |
| `set_fft_spots` | Find Spots, Measure at… (whole bins from the centre), selects and removes spots, puts spots in or out of the mask |
| `set_diffraction` | the Diffraction room's Centre (typed, or a fitted ring's), Calibration (standard, ring, Calibrate on Ring, Clear, typed Δq and kV for a file without them, camera and pixel pitch), Phases (a standard as the crystal, k_max, tolerance; a library phase through `add_phase`), the annulus, Fit Ring, the tool and the log display |
| `set_diffraction_marks` | adds a spot as a click on the pattern does, selects a ring or spot, removes one or all |
| `new_simulation` | File > New Simulation: a simulated pattern with no measured one, in the Diffraction room with the simulated spots on; a window that holds a file gives it a tab of its own |
| `index_pattern` | presses Index (optionally Remove Spots first, and Fit scale on or off) and answers at once with `get_spot_table`'s answer; refused in the room's words without a centre, a scale, a beam energy or a crystal |
| `set_zone_axis` | the Index section's zone axis (as typed) and turn, its Solution stepper and Flip 180°, and the Tilt tool's tilt and ⌥ turn; answers with the orientation's place once set by hand |
| `simulate_pattern` | the Simulation section's overlay, labels, double diffraction and excitation error; answers with the simulated spots on the pattern (each flagged when double diffraction adds it) or why there are none |
| `add_phase` | adds a Materials Project entry by its id to the library as Add Phase… does (the open service, or the person's own key from Settings; no tool takes or shows a key), and with `show` shows it in the Diffraction room; answers at once, `list_phases` says when it is in |
| `set_phase_lattice` | sets a library phase's free lattice parameters (DiffractoKit's `editingLattice`: tied ones follow, a change of Laue class is refused); the Diffraction room takes the edit when it shows the phase |
| `set_simulation` | the Simulation document's settings through its sections' controls: the library phase and zone axis, thickness and Build with Strain, defocus or Scherzer and the thickness shown, voltage, optics preset, Cs, spreads, aperture, field of view, the atom columns ringed on the image, frozen phonons with σ and configurations, Place Beside (the measured image, layout, rotation, inset size) |
| `run_simulation` | Show HRTEM Image and its run: the static lattice's exit waves, or Simulate and Continue with frozen phonons; `stop_run` stops it and keeps the configurations done |
| `set_relationship` | the Precipitate section: the precipitate, its two parallel pairs, which variants are shown, the overlay, double diffraction with the matrix; answers the variants, their groups and the sentences |
| `powder_pattern` | the Powder section (rings or X-ray, the line, the range or reach, a phase to compare with, overlap marks); writes the peak table CSV or the .xy profile into the Agent folder |
| `find_phases` | the Find Phases sheet: Fit scale, Rank (answers at once, `running` until it lands) and Use in Room; answers the ranked rows, their sentences and the ties |
| `plan_tilt` | the Holder section: the tilts now, the limits, the tilt axis typed, forgotten or calibrated from another open pattern, a zone axis picked on the map; writes the Tilt List CSV into the Agent folder |
| `set_dynamical` | the Simulation section's Intensities: Kinematic or Dynamical (Dynamical runs the multislice, as the section does) and the stored thickness shown; Dynamical is refused with the section's sentence while an atom model is the source |
| `set_cbed` | the Simulation section's Beam (Parallel or Convergent) and CBED settings: semiangle or Fit Discs, largest thickness, angular step, pattern edge, and the stored pattern shown; with an atom model as the source Fit Discs is refused and `read_cbed` gives the overlay's refusal |
| `run_cbed` | Show CBED Pattern: opens the pattern in the Diffraction room and runs the probe; refused with the section's words while it cannot run |
| `stop_cbed` | the CBED section's Stop; the patterns stored stay |
| `measure_thickness` | Measure Thickness on the pattern shown: the two-beam fit across the diffracted disc (Kelly et al. 1975); `read_thickness` gives the verdict |
| `use_measured_thickness` | Use in Simulation: the thickness found becomes the Simulation document's specimen thickness; refused while the document simulates an atom model (its thickness is the model's own) |
| `set_stem` | the STEM section: semiangle, defocus or Scherzer, scan step or Nyquist, Collect to, and the detector (a preset, or Custom with inner and outer angles on whole rings) |
| `run_stem` | Show STEM Image and Simulate or Continue; the image fills as it is computed; refused with the section's words while it cannot run |
| `stop_stem` | the STEM section's Stop; the positions done stay and `run_stem` continues |
| `select_grains` | selects grains as the grain table does, or none |

The EDS tools are EMSuiteUI's `EDXAgentTools`, written once and registered by both apps.

## Coverage

`macTEM/App/AgentDoorCoverage.swift` lists every control in the app, by its accessibility identifier, with how an agent
reaches it: the tool that does it, already seen in a get tool's answer, left to the person on purpose (with the reason), or a
gap with its open issue. `AgentDoorCoverageTests` fails when a control has no row, a row names a tool the door does not have,
or a row outlives its control, so a new control cannot ship undecided. The menu bar has its own table beside it, `menuItems`: every item of the File, View, Image, Workspace and Help menus by its title as the source writes it, held by the same test. Every tool that acts is in the table above, and the test fails when one is not. A feature that adds a room action adds its row in the same PR, and the release walk reads the gaps. The gaps left are the crystal pane's Unit cell switch and the Simulation document's Microscope section (#846), and the EDS room's polygon and line regions and Pin Region (#885). A room's open panel is the
person's; `open_file` opens a file of the Agent folder and `open_demo` the shipped demos. The EDS room's own controls are
EMSuiteUI's and are reached through its tools.

## Code

`macTEM/App/`: `AgentDoorTools.swift` (the door and the tools that look), `AgentDoorRooms.swift` (the tools that act),
`AgentDoorPatterns.swift` (the toolbar verb and the Patterns room), `AgentDoorIndexing.swift` (the Indexing room), `AgentDoorMaps.swift` (the Maps room), `AgentDoorEELS.swift` (the EELS room), `AgentDoorImage.swift` (the Image room), `AgentDoorFFT.swift` (the FFT room), `AgentDoorDiffraction.swift` (the Diffraction room), `AgentDoorIndex.swift` (Index, the Spots table and the simulated spots), `AgentDoorPhases.swift` (the phase library), `AgentDoorSession.swift` (the SEM session),
`AgentDoorGuide.swift` (the workflow guide) and `AgentDoorCoverage.swift`. Settings > Agents is `AgentSettingsView` on
EMSuiteUI's `AgentDoorSettingsSection`.
