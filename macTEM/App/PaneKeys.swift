//
//  PaneKeys.swift
//  Role: the keys of the FFT room's and the Image room's panes — arrows, Delete, ⌘C and Escape — and Edit > Copy and
//        Delete, all through ONE routing function per room (open-items "Arrows, ⌫ and ⌘C on a pane do nothing"; design:
//        ).
//
//  WHY ONE CONTAINER PER ROOM: the panes' own focusable leaves (`.focusable()` + `@FocusState` + `.onMoveCommand`…) never
//  held focus in this shell — focus was granted and withdrawn within the click — while a room-level focusable ancestor with
//  `.onKeyPress` does receive ←, → and ⌫ (experiment E2; 2 of 2).
//  This is mac4DSTEM's arrangement (`WorkspaceView`: `.focusable().focusEffectDisabled().onKeyPress(phases: .down)` on the
//  pane container). The room's root carries it (`FFTKeyedRoom`, `ImageKeyedRoom` below); the panes hold no focus, no
//  `@FocusState` and no `on…Command`; a pane that has been pressed tells the room which pane the keys are for.
//
//  THE PURE PART (`PaneKey`, `PaneKeyAction`, `PaneKeyRouter`): a key plus the room's selection state gives the action, or
//  nil — not ours, so the press goes on. Nothing in it touches a view, so a test pins every row of the table.
//  THE PERFORMERS (`FFTRoomKeys`, `ImageRoomKeys`): build the state from the owners, route, and do. The key press and the
//  Edit menu go through the SAME `handle`, and the menu items are enabled exactly when the router has an action for them.
//
//  EDIT > COPY AND DELETE are the system's items, validated through the responder chain: the container's `onCopyCommand` /
//  `onDeleteCommand` take an optional action, and nil (no action for the key in this state) disables the item. A custom
//  `CommandGroup(replacing: .pasteboard)` would take Copy from the inspector's text fields (a focused scene value outlives the
//  room's focus), and a focused value may not hold closures (swiftui-specialist, environment.md).
//
//  APPKIT is used here for `NSPasteboard` only (the key path of ⌘C; the menu path hands the system an `NSItemProvider`). The
//  writer below is the app's one way onto the pasteboard: the error alert's Copy Details writes through it too.
//

import SwiftUI
import AppKit
import TEMCore
import TEMSession

// MARK: - The pure part

/// A key a pane answers. Built from a SwiftUI key press's key and modifiers (`init?(key:modifiers:)`, pure, so a test
/// builds one without a `KeyPress`).
nonisolated enum PaneKey: Equatable {
    case arrow(MoveCommandDirection)
    /// ⌥ with an arrow (⇧ too, for the coarse step): moves the Image room's mark cursor and the Diffraction room's spot cursor
    /// (UI/MarkCursor.swift), so the plain arrows stay the frame keys of a stack.
    case cursorArrow(MoveCommandDirection)
    case delete
    case copy
    case escape
    /// Return: sets a point at the cursor (the Image room) or adds a spot there (the Diffraction room).
    case enter
    /// Home and End: a stack's first and last frame.
    case home
    case end

    /// nil for any other key, and for these with a modifier they do not take: an arrow takes ⇧ (ten pixels), ⌥ (the cursor's arrow)
    /// or both, ⌘C takes ⌘ alone, ⌫, Escape, Return, Home and End none. Only the four real modifiers count: a real arrow press carries the numeric-pad and function flags
    /// (raw 96, ⇧← 98) and Forward Delete the function flag (64), as the refuter measured on a hosted view; Caps Lock too is
    /// not a modifier of the key.
    init?(key: KeyEquivalent, modifiers: EventModifiers) {
        let held = modifiers.intersection([.shift, .control, .option, .command])
        switch key {
        case .leftArrow where held.isSubset(of: .shift): self = .arrow(.left)
        case .rightArrow where held.isSubset(of: .shift): self = .arrow(.right)
        case .upArrow where held.isSubset(of: .shift): self = .arrow(.up)
        case .downArrow where held.isSubset(of: .shift): self = .arrow(.down)
        case .leftArrow where held.contains(.option) && held.isSubset(of: [.option, .shift]): self = .cursorArrow(.left)
        case .rightArrow where held.contains(.option) && held.isSubset(of: [.option, .shift]): self = .cursorArrow(.right)
        case .upArrow where held.contains(.option) && held.isSubset(of: [.option, .shift]): self = .cursorArrow(.up)
        case .downArrow where held.contains(.option) && held.isSubset(of: [.option, .shift]): self = .cursorArrow(.down)
        case .return where held.isEmpty: self = .enter
        case .home where held.isEmpty: self = .home
        case .end where held.isEmpty: self = .end
        case .delete where held.isEmpty, .deleteForward where held.isEmpty: self = .delete
        case .escape where held.isEmpty: self = .escape
        case KeyEquivalent("c") where held == .command: self = .copy
        default: return nil
        }
    }

    /// Only an arrow repeats while held, as `onMoveCommand` did (the cursor's arrows too); ⌫, ⌘C and Return fire once per press.
    var repeats: Bool {
        switch self {
        case .arrow, .cursorArrow: true
        default: false
        }
    }

    /// The press's key, modifiers and phase read to the key it is for, or nil when it is not ours (or a repeat of a key that
    /// does not repeat). The one reading both rooms' `handle(_ press:)` use, so a test pins it without a `KeyPress`.
    static func read(key: KeyEquivalent, modifiers: EventModifiers, isRepeat: Bool) -> (key: PaneKey, shift: Bool)? {
        guard let pane = PaneKey(key: key, modifiers: modifiers), !isRepeat || pane.repeats else { return nil }
        return (pane, modifiers.contains(.shift))
    }
}

/// What a key does in a room.
nonisolated enum PaneKeyAction: Equatable {
    case nudgeRegion(MoveCommandDirection, step: Int)
    case clearRegion
    case deleteSpot
    case copySpot
    case deleteMark
    case copyMark
    case cancelAngle
    /// A stack's frame: `by` frames on, or the first or the last.
    case stepFrame(by: Int)
    case firstFrame
    case lastFrame
    /// The cursor one pixel (`fine`) or one coarse step (`MarkCursor.step`) that way.
    case moveCursor(MoveCommandDirection, fine: Bool)
    /// A point set at the cursor (the Image room), a spot added there (the Diffraction room).
    case setPoint
}

/// The FFT room's two panes: the keys are for the one pressed last.
nonisolated enum FFTKeyPane: Equatable {
    case source
    case spectrum
}

/// What the FFT room's keys depend on.
nonisolated struct FFTKeyState: Equatable {
    /// The pane pressed last; nil until a pane has been pressed (the keys are then for neither).
    var active: FFTKeyPane?
    /// The source pane shows the file (the Original view) and a region exists: the outline is there to move or clear.
    var regionShown: Bool
    /// The spectrum is shown and a spot on it is selected.
    var spotSelected: Bool
}

/// What the Image room's keys depend on.
nonisolated struct ImageKeyState: Equatable {
    var markSelected: Bool
    /// A mark waiting for its next point: an angle whose first arm is drawn, or a point the cursor holds (`MarkCursorState`,
    /// UI/MarkCursor.swift).
    var angleInProgress: Bool
    /// The item is a stack: ← and → step its frames, Home and End go to its ends.
    var stack: Bool = false
    /// Distance, Angle or Profile is chosen: ⌥ and an arrow move the mark cursor, Return sets a point there.
    var measuring: Bool = false
}

/// What the Diffraction room's pattern keys depend on.
nonisolated struct DiffractionKeyState: Equatable {
    var stack: Bool
    /// The Spot tool is chosen: a click adds a spot, so ⌥ and an arrow move the spot cursor and Return adds one there.
    var addsSpots: Bool
}

nonisolated enum PaneKeyRouter {
    /// Source pane: the arrows nudge the region (⇧ ten pixels), ⌫ clears it. Spectrum pane: ⌫ deletes the selected spot, ⌘C
    /// copies its line. Anything else, or the other pane, is nil.
    static func fft(_ key: PaneKey, shift: Bool, state: FFTKeyState) -> PaneKeyAction? {
        switch (key, state.active) {
        case (.arrow(let direction), .source?):
            return state.regionShown ? .nudgeRegion(direction, step: shift ? 10 : 1) : nil
        case (.delete, .source?):
            return state.regionShown ? .clearRegion : nil
        case (.delete, .spectrum?):
            return state.spotSelected ? .deleteSpot : nil
        case (.copy, .spectrum?):
            return state.spotSelected ? .copySpot : nil
        default:
            return nil
        }
    }

    /// ⌫ and ⌘C act on the selected mark; Escape drops an angle (or a cursor's point) that is in progress. ← and → step a stack's
    /// frames, Home and End go to its ends (↑ and ↓ are nobody's). While a measuring tool is chosen, ⌥ and an arrow move the mark
    /// cursor one pixel, ⌥⇧ and an arrow one coarse step, and Return sets a point there (macEM#509, #510).
    static func image(_ key: PaneKey, shift: Bool = false, state: ImageKeyState) -> PaneKeyAction? {
        switch key {
        case .delete: state.markSelected ? .deleteMark : nil
        case .copy: state.markSelected ? .copyMark : nil
        case .escape: state.angleInProgress ? .cancelAngle : nil
        case .arrow(let direction): frameStep(direction, stack: state.stack)
        case .home: state.stack ? .firstFrame : nil
        case .end: state.stack ? .lastFrame : nil
        case .cursorArrow(let direction): state.measuring ? .moveCursor(direction, fine: !shift) : nil
        case .enter: state.measuring ? .setPoint : nil
        }
    }

    /// The Diffraction pattern's keys: a stack's frames as in the Image room; in the Spot tool, ⌥ and an arrow move the spot cursor
    /// (⌥⇧ the coarse step) and Return adds a spot there. Nothing else is the pattern's (⌫ is the readout table's).
    static func diffraction(_ key: PaneKey, shift: Bool = false, state: DiffractionKeyState) -> PaneKeyAction? {
        switch key {
        case .arrow(let direction): frameStep(direction, stack: state.stack)
        case .home: state.stack ? .firstFrame : nil
        case .end: state.stack ? .lastFrame : nil
        case .cursorArrow(let direction): state.addsSpots ? .moveCursor(direction, fine: !shift) : nil
        case .enter: state.addsSpots ? .setPoint : nil
        case .delete, .copy, .escape: nil
        }
    }

    /// ← one frame back and → one on, in a stack; ↑ and ↓ nothing.
    private static func frameStep(_ direction: MoveCommandDirection, stack: Bool) -> PaneKeyAction? {
        guard stack else { return nil }
        switch direction {
        case .left: return .stepFrame(by: -1)
        case .right: return .stepFrame(by: 1)
        default: return nil
        }
    }
}

// MARK: - The pasteboard

/// Where a ⌘C that arrives as a key, and the error alert's Copy Details, write their text. The system's general pasteboard in
/// the app; a test passes its own, so no test touches the owner's clipboard.
@MainActor
protocol PaneTextWriter {
    func write(_ text: String)
}

struct SystemPaneTextWriter: PaneTextWriter {
    func write(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

// MARK: - The FFT room

/// The FFT room's keys, built from the owner at the moment of use.
@MainActor
struct FFTRoomKeys {
    let analysis: FFTAnalysis
    var active: FFTKeyPane?
    /// The file's size, which the region is held inside (the Original view draws the region, and shows the file).
    var sourceSize: (width: Int, height: Int)
    var writer: any PaneTextWriter = SystemPaneTextWriter()
    /// The window's undo manager, for Edit > Undo of a spot ⌫ removed (#325); nil registers no undo.
    var undoManager: UndoManager?

    var state: FFTKeyState {
        let selected = analysis.selection.flatMap { id in analysis.spots.first { $0.id == id } }
        return FFTKeyState(active: active,
                           regionShown: analysis.sourceView == .original && analysis.region != nil,
                           spotSelected: selected != nil && analysis.spectrum != nil && analysis.spectrumFailure == nil)
    }

    func route(_ key: PaneKey, shift: Bool = false) -> PaneKeyAction? {
        PaneKeyRouter.fft(key, shift: shift, state: state)
    }

    /// Edit > Copy and Delete are enabled exactly when the keys would act.
    var canCopy: Bool { route(.copy) != nil }
    var canDelete: Bool { route(.delete) != nil }

    /// A key press, or an Edit menu item: true when it was ours and was done.
    @discardableResult
    func handle(_ key: PaneKey, shift: Bool = false) -> Bool {
        guard let action = route(key, shift: shift) else { return false }
        perform(action)
        return true
    }

    /// A key press, as its parts (a test has no `KeyPress`): ours and done is `.handled`.
    func handle(key: KeyEquivalent, modifiers: EventModifiers, isRepeat: Bool = false) -> KeyPress.Result {
        guard let read = PaneKey.read(key: key, modifiers: modifiers, isRepeat: isRepeat) else { return .ignored }
        return handle(read.key, shift: read.shift) ? .handled : .ignored
    }

    /// A SwiftUI key press.
    func handle(_ press: KeyPress) -> KeyPress.Result {
        handle(key: press.key, modifiers: press.modifiers, isRepeat: press.phase == .repeat)
    }

    private func perform(_ action: PaneKeyAction) {
        switch action {
        case .nudgeRegion(let direction, let step):
            guard let region = analysis.region else { return }
            analysis.setRegion(FFTRegionGeometry.nudged(region, direction, step: step, width: sourceSize.width, height: sourceSize.height),
                               committed: true)
        case .clearRegion:
            analysis.setRegion(nil, committed: true)
        case .deleteSpot:
            if let id = analysis.selection { FFTSpotUndo.remove([id], in: analysis, undoManager: undoManager) }
        case .copySpot:
            if let text = copyText() { writer.write(text) }
        case .deleteMark, .copyMark, .cancelAngle, .stepFrame, .firstFrame, .lastFrame, .moveCursor, .setPoint:
            break
        }
    }

    /// The selected spot's line, with what was transformed (`FFTPaneFormat.copyLine`).
    func copyText() -> String? {
        guard let id = analysis.selection, let spot = analysis.spots.first(where: { $0.id == id }),
              let spectrum = analysis.spectrum else { return nil }
        let subject = FFTPaneFormat.subject(crop: spectrum.key.crop, width: spectrum.width, height: spectrum.height)
        return FFTPaneFormat.copyLine(spot, subject: subject)
    }

    /// What Edit > Copy hands the system: the same line, or nothing when the keys would not copy.
    func copyProviders() -> [NSItemProvider] {
        guard canCopy, let text = copyText() else { return [] }
        return [NSItemProvider(object: text as NSString)]
    }
}

/// The FFT room's root: focusable, key-pressed, and the owner of Edit > Copy and Delete for the room.
struct FFTKeyedRoom: ViewModifier {
    let analysis: FFTAnalysis
    let imageWidth: Int
    let imageHeight: Int
    @Binding var active: FFTKeyPane?
    @Environment(\.undoManager) private var undoManager

    func body(content: Content) -> some View {
        let keys = FFTRoomKeys(analysis: analysis, active: active, sourceSize: (imageWidth, imageHeight), undoManager: undoManager)
        return content
            .focusable()
            // DEVIATION (deliberate, mac4DSTEM's arrangement): no focus ring. The container is the whole room, and a room-sized
            // ring on every click would be wrong; the cost is that Full Keyboard Access shows no ring on this stop. The
            // inspector's controls stay reachable by Tab, and the keys here are the pointer's companions (design.md).
            .focusEffectDisabled()
            // A held arrow repeats, as `onMoveCommand` did; ⌫ and ⌘C do not (`PaneKey.repeats`).
            .onKeyPress(phases: [.down, .repeat]) { keys.handle($0) }
            .onCopyCommand(perform: keys.canCopy ? { keys.copyProviders() } : nil)
            .onDeleteCommand(perform: keys.canDelete ? { _ = keys.handle(.delete) } : nil)
    }
}

/// A pane that says, on any press inside it (picture, header or footer, a click or the start of a pan), that the room's keys are
/// now for it. SIMULTANEOUS, so the region's and ZoomPan's own gestures are not disturbed; written only when it changes.
struct FFTPanePress: ViewModifier {
    let pane: FFTKeyPane
    @Binding var keyPane: FFTKeyPane?

    func body(content: Content) -> some View {
        content.simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in
            if keyPane != pane { keyPane = pane }
        })
    }
}

// MARK: - The Image room

/// An angle whose first arm is drawn, waiting for its third point.
nonisolated struct AngleArm: Equatable {
    var a: ImagePoint
    var vertex: ImagePoint
}

/// The Image room's keys, built from the owner at the moment of use.
@MainActor
struct ImageRoomKeys {
    let measurements: ImageMeasurements
    /// The text a mark is copied as (the Measure section's value).
    let label: (ImageMark) -> String
    var angleInProgress: Bool
    let cancelAngle: () -> Void
    var writer: any PaneTextWriter = SystemPaneTextWriter()
    /// The owner whose image ⌫'s Edit > Undo puts the mark back on, and the window's undo manager (#325); nil registers no undo.
    var session: ImageSession?
    var undoManager: UndoManager?
    /// The stack's frame keys; nil when the item is not a stack.
    var frames: StackFrameKeys?
    /// The mark cursor's keys while Distance, Angle or Profile is chosen (macEM#509); nil with Pan.
    var cursor: CursorKeys?

    var state: ImageKeyState {
        ImageKeyState(markSelected: measurements.mark(measurements.selection) != nil, angleInProgress: angleInProgress,
                      stack: frames != nil, measuring: cursor != nil)
    }

    func route(_ key: PaneKey, shift: Bool = false) -> PaneKeyAction? {
        PaneKeyRouter.image(key, shift: shift, state: state)
    }

    var canCopy: Bool { route(.copy) != nil }
    var canDelete: Bool { route(.delete) != nil }

    @discardableResult
    func handle(_ key: PaneKey, shift: Bool = false) -> Bool {
        guard let action = route(key, shift: shift) else { return false }
        perform(action)
        return true
    }

    func handle(key: KeyEquivalent, modifiers: EventModifiers, isRepeat: Bool = false) -> KeyPress.Result {
        guard let read = PaneKey.read(key: key, modifiers: modifiers, isRepeat: isRepeat) else { return .ignored }
        return handle(read.key, shift: read.shift) ? .handled : .ignored
    }

    func handle(_ press: KeyPress) -> KeyPress.Result {
        handle(key: press.key, modifiers: press.modifiers, isRepeat: press.phase == .repeat)
    }

    private func perform(_ action: PaneKeyAction) {
        switch action {
        case .deleteMark:
            if let id = measurements.selection { MarkUndo.remove([id], in: measurements, session: session, undoManager: undoManager) }
        case .copyMark:
            if let text = copyText() { writer.write(text) }
        case .cancelAngle:
            cancelAngle()
        case .stepFrame(let delta):
            frames?.step(delta)
        case .firstFrame:
            frames?.first()
        case .lastFrame:
            frames?.last()
        case .moveCursor(let direction, let fine):
            cursor?.move(direction, fine)
        case .setPoint:
            cursor?.set()
        case .nudgeRegion, .clearRegion, .deleteSpot, .copySpot:
            break
        }
    }

    func copyText() -> String? {
        measurements.mark(measurements.selection).map(label)
    }

    func copyProviders() -> [NSItemProvider] {
        guard canCopy, let text = copyText() else { return [] }
        return [NSItemProvider(object: text as NSString)]
    }
}

/// A stack's frame keys on its owners at the moment of use: ← and → one frame, Home and End the ends (what `StackArrowKeys` does in
/// the rooms without keys of their own).
@MainActor
struct StackFrameKeys {
    let step: @MainActor (Int) -> Void
    let first: @MainActor () -> Void
    let last: @MainActor () -> Void

    /// `item`'s frame keys, nil when it is not a stack.
    static func of(_ item: OpenItem, in items: OpenItems) -> StackFrameKeys? {
        guard let stack = item.stack else { return nil }
        let end = stack.frameCount - 1
        return StackFrameKeys(step: { items.stepFrame(item, by: $0) },
                              first: { items.showFrame(item, to: 0) },
                              last: { items.showFrame(item, to: end) })
    }
}

/// A cursor's keys (UI/MarkCursor.swift): ⌥ and an arrow move it (`fine`: one pixel, else the coarse step), Return sets a point or
/// adds a spot there.
@MainActor
struct CursorKeys {
    let move: @MainActor (MoveCommandDirection, Bool) -> Void
    let set: @MainActor () -> Void
}

/// Gives the Image room's keyed container the keyboard: a press on the marks' overlay, whose own drag is a child gesture that the
/// container's press gesture does not see (`SEMRoomKeys`, `SEMMapPress`). `ImageKeyedRoom` puts it in the environment.
struct ImageRoomFocus {
    let take: () -> Void
}

extension EnvironmentValues {
    @Entry var imageRoomFocus = ImageRoomFocus(take: {})
}

/// The room's one keyboard target, bound by value as `SEMRoomFocus` binds its own (a Bool reads true while a descendant has it).
enum PaneKeyTarget: Hashable {
    case room
}

/// The Image room's root: focusable, key-pressed, and the owner of Edit > Copy and Delete for the room. It is the room's ONE keyed
/// container, a stack's frame keys too (`StackArrowKeys` stays off in this room): a second focusable ancestor took the keyboard on
/// every click, so this container's Escape, Delete and the mark cursor's keys never reached it on a stack (macEM#509). A press on the
/// pane gives it the keyboard, and it is the window's default focus while nothing else claims it, as `SEMRoomFocus`.
struct ImageKeyedRoom: ViewModifier {
    let item: OpenItem
    let items: OpenItems
    /// The angle's arm and the mark cursor's state (UI/MarkCursor.swift), read at each key (`MarkCursorModel`): a point the cursor
    /// holds is an unfinished mark too, which Escape drops with the arm.
    let cursor: MarkCursorModel
    /// The picture the cursor's points are set on. The tool's kind of mark is read from the app at each key (nil with Pan: the
    /// cursor's keys are off).
    let basis: MarkCursorBasis
    @Environment(AppState.self) private var appState
    @Environment(\.undoManager) private var undoManager
    @FocusState private var focus: PaneKeyTarget?

    func body(content: Content) -> some View {
        // The session, never its image: a key closure SwiftUI keeps after the pane is gone keeps no pixels alive (#577).
        let session = item.session
        let state = appState
        let cursor = cursor, measurements = item.measurements, basis = basis, undoManager = undoManager
        let frames = StackFrameKeys.of(item, in: items)
        // Built at each press, from owners read now: SwiftUI may answer a key with the closure of an earlier update, whose values
        // (the cursor, a held point, the tool) are a key behind (the CI journey, macEM#509).
        let now = {
            Self.keys(image: { session.imageOrBlank }, measurements: measurements, angleArm: cursor.armBinding,
                      markCursor: cursor.stateBinding, kind: state.imageRoomTools.tool.markKind, basis: basis, frames: frames,
                      session: session, undoManager: undoManager,
                      refused: { SessionPanels.markRefused($0, .added, appState: state) })
        }
        let keys = now()
        return content
            .focusable()
            .focusEffectDisabled()   // DEVIATION as `FFTKeyedRoom`'s, named there
            // A held arrow repeats (the frames, the cursor); ⌫, ⌘C and Return do not (`PaneKey.repeats`).
            .onKeyPress(phases: [.down, .repeat]) { now().handle($0) }
            .onCopyCommand(perform: keys.canCopy ? { keys.copyProviders() } : nil)
            .onDeleteCommand(perform: keys.canDelete ? { _ = keys.handle(.delete) } : nil)
            .focused($focus, equals: .room)
            .defaultFocus($focus, .room)
            // Any press on the pane (a click, a drag, the start of a pan) gives the room the keyboard, simultaneously, so the marks' and
            // the zoom's gestures are not disturbed (`FFTPanePress`, `SEMMapPress`).
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in if focus != .room { focus = .room } })
            // A press on a measuring tool's overlay is the overlay's drag: it takes the keyboard for the room itself.
            .environment(\.imageRoomFocus, ImageRoomFocus { if focus != .room { focus = .room } })
    }

    /// The room's keys on the owners now, so a test drives the ones the room has: Escape routes while an angle's arm or a point the
    /// cursor holds waits, and drops both; ⌥ and an arrow move the cursor and Return sets a point while a tool is chosen (`kind`).
    /// `image` is read at each use, never held.
    static func keys(image: @escaping @MainActor () -> CalibratedImage, measurements: ImageMeasurements,
                     angleArm arm: Binding<AngleArm?>, markCursor cursor: Binding<MarkCursorState>,
                     kind: ImageMark.Kind? = nil, basis: MarkCursorBasis? = nil, frames: StackFrameKeys? = nil,
                     session: ImageSession? = nil, undoManager: UndoManager? = nil,
                     refused: @escaping @MainActor (SessionLineage.Refusal) -> Void = { _ in }) -> ImageRoomKeys {
        let shown = image()
        let x = shown.x, y = shown.y
        let at = basis ?? MarkCursorBasis(width: shown.width, height: shown.height, version: 0)
        var keys = ImageRoomKeys(measurements: measurements, label: { MarkFormat.value($0, x: x, y: y) },
                                 angleInProgress: arm.wrappedValue != nil || cursor.wrappedValue.first != nil,
                                 cancelAngle: { arm.wrappedValue = nil; cursor.wrappedValue.first = nil },
                                 session: session, undoManager: undoManager)
        keys.frames = frames
        if let kind {
            let actions: @MainActor () -> MarkCursorActions = { MarkCursorActions(image: image(), measurements: measurements, kind: kind, basis: at) }
            keys.cursor = CursorKeys(move: { direction, fine in
                                         guard let step = MarkCursor.Move(direction) else { return }
                                         actions().move(step, fine: fine, cursor: cursor)
                                     },
                                     set: { actions().setPoint(cursor: cursor, arm: arm, refused: refused) })
        }
        return keys
    }
}

// MARK: - The Diffraction room

/// The Diffraction pattern's keys, built from the owner at the moment of use: a stack's frames, and in the Spot tool the spot cursor's
/// ⌥-arrows and Return (macEM#509).
@MainActor
struct DiffractionPatternKeys {
    var frames: StackFrameKeys?
    /// The spot cursor's keys while a click adds a spot; nil otherwise.
    var cursor: CursorKeys?

    var state: DiffractionKeyState { DiffractionKeyState(stack: frames != nil, addsSpots: cursor != nil) }

    @discardableResult
    func handle(_ key: PaneKey, shift: Bool = false) -> Bool {
        guard let action = PaneKeyRouter.diffraction(key, shift: shift, state: state) else { return false }
        switch action {
        case .stepFrame(let delta): frames?.step(delta)
        case .firstFrame: frames?.first()
        case .lastFrame: frames?.last()
        case .moveCursor(let direction, let fine): cursor?.move(direction, fine)
        case .setPoint: cursor?.set()
        default: return false
        }
        return true
    }

    func handle(key: KeyEquivalent, modifiers: EventModifiers, isRepeat: Bool = false) -> KeyPress.Result {
        guard let read = PaneKey.read(key: key, modifiers: modifiers, isRepeat: isRepeat) else { return .ignored }
        return handle(read.key, shift: read.shift) ? .handled : .ignored
    }

    func handle(_ press: KeyPress) -> KeyPress.Result {
        handle(key: press.key, modifiers: press.modifiers, isRepeat: press.phase == .repeat)
    }
}

/// The Diffraction pattern's keyed container: the room's frame keys and the spot cursor's, focusable as `ImageKeyedRoom` (and so
/// `StackArrowKeys` stays off in this room). Only the pattern: the readout table keeps its own keyboard (⌫, ↑ and ↓).
struct DiffractionKeyedPane: ViewModifier {
    let keys: DiffractionPatternKeys
    @FocusState private var focus: PaneKeyTarget?

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()   // DEVIATION as `FFTKeyedRoom`'s, named there
            .onKeyPress(phases: [.down, .repeat]) { keys.handle($0) }
            .focused($focus, equals: .room)
            .defaultFocus($focus, .room)
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in if focus != .room { focus = .room } })
    }
}
