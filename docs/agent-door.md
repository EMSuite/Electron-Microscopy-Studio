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
| `get_workflow_guide` | how a person works through a file here and how to judge each step (topics `overview`, `eds`, `patterns`, `indexing`); read first |
| `list_windows` | the open windows (`w1`, `w2`, ...), each with its shown file, room and number of open files (the door's own tool) |
| `get_window` | the room, the open files (size, calibration, voltage once read), the shown file's number of results, the status line, any error |
| `get_image` | the shown image as Export Image… draws it (display window, colormap, scale bar, marks), longest side up to 1024 px per `scale` step |
| `get_results` | the shown file's finished measurements as Export Results… writes them (CSV) |
| `get_log` | the window's Output lines |
| `get_eds` | the EDS room: file, picked elements and roles, region, kept regions, line windows' net counts with σ, Auto ID's suggestions, the results table or why the fit failed |
| `get_eds_maps` | the EDS maps as the room's Maps as PNG… draws them |
| `get_patterns` | the Patterns room: scan and pattern size, the file's calibration, the picked position, the map and grid, the colour mix, every processing setting (in `set_pattern_processing`'s names) with each stage's state, why Process is refused, NLPAR's λ, what is running |
| `get_patterns_picture` | `which` map or pattern: the Patterns room's pane as its Export section draws it (Map PNG…, Pattern PNG…); a small one is enlarged by a whole factor, no smoothing |
| `get_indexing` | the Indexing room: where its patterns come from, the phases, the method and every Hough, Dictionary and Refine setting (in `set_indexing`'s names), the master patterns open, why Index is refused, the run on screen (state, points indexed per phase, mean confidence or score and fit), the picked point's solution and detected bands, Compare's summary, what is running |
| `get_indexing_picture` | `which` map (the layer as Export's Map PNG… draws it), pattern (as indexed, without the band overlay) or best_match (a Dictionary run's) |

Every picture and number comes from the code that draws or exports it for the person, so the agent judges what the
person sees. Numbers in JSON fields use a point; the status and Output lines are the window's own text, in the Mac's Region.

## Tools that act

Behind "Let agents run analyses". Each goes through the entry point its control uses and leaves an Output line that starts
"An agent", so the person can tell the agent's steps from their own.

| Tool | Does |
|---|---|
| `select_room` | moves the window to a room, as the room bar does; a room the files do not fill is refused with the room bar's reason |
| `open_demo` | opens a demo document in its room, as Help > Open Demo Data does |
| `set_eds` | picks and removes elements, sets an element's role (quantify or fit only), chooses the region (whole, rectangle, ellipse, a kept region) |
| `run_eds` | Auto ID, Quantify or Stop; answers at once, `get_eds` says busy until done |
| `run_room` | presses the shown room's toolbar verb, as ⌘R does (Quantify, Run, Process, Index, Segment); refused with the button's own words while it cannot run |
| `stop_run` | Stop, as ⌘. does: the shown room's run or open, or a run left going in another room |
| `select_scan_position` | picks a scan position (x column, y row) as a click on the Patterns or Indexing room's map does; in the Indexing room the pattern pane shows it as indexed |
| `set_patterns` | the Virtual images section (grid, map, tile, colour mix, tiles pane) and the pattern's Raw/Processed switch; says when a new grid also dropped the tile map or the mix |
| `set_pattern_processing` | the Processing sections' settings (static and dynamic background, intensity, FFT filter, binning, neighbour averaging, NLPAR), only those given |
| `set_indexing` | the Indexing room's Display (layer, detected bands, simulation, Compare A and B), Method, Hough, Dictionary and Refine settings, only those given; `reset` goes back to a section's defaults first |
| `set_indexing_phase` | adds a built-in phase; turns a phase on or off, sets its reflector list or its master pattern, or removes it |
| `open_in_maps` | Open in Maps: the run on screen goes to the Maps room |

The EDS tools are EMSuiteUI's `EDXAgentTools`, written once and registered by both apps.

## Coverage

`macTEM/App/AgentDoorCoverage.swift` lists every control in the app, by its accessibility identifier, with how an agent
reaches it: the tool that does it, already seen in a get tool's answer, left to the person on purpose (with the reason), or a
gap with its open issue. `AgentDoorCoverageTests` fails when a control has no row, a row names a tool the door does not have,
or a row outlives its control, so a new control cannot ship undecided. The gaps are #558's: the Image, FFT, EELS, Diffraction
and Maps rooms, which get their tools one room per pull request, and the Patterns room's Kikuchi overlay. Opening a file
(an open panel) is the person's; `open_demo` opens the shipped demos. The EDS room's own controls are
EMSuiteUI's and are reached through its tools.

## Code

`macTEM/App/`: `AgentDoorTools.swift` (the door and the tools that look), `AgentDoorRooms.swift` (the tools that act),
`AgentDoorPatterns.swift` (the toolbar verb and the Patterns room), `AgentDoorIndexing.swift` (the Indexing room),
`AgentDoorGuide.swift` (the workflow guide) and `AgentDoorCoverage.swift`. Settings > Agents is `AgentSettingsView` on
EMSuiteUI's `AgentDoorSettingsSection`.
