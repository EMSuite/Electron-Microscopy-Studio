//
//  DiffractionAnalysis.swift
//  Role: the Diffraction room's owner for one open file (design section 2): the centre, the calibration, the crystal, the rings and the
//        spots the user measured, and the readout the room and its exports show. It holds no pixels of the image (the room hands the
//        image to each action), so it stays while the item is cold.
//
//  Nothing here makes a number: `TEMCore/Diffraction` is DiffractoKit's ring fit, calibration, scale and indexing; this owner decides WHEN
//  to ask. A ring fit runs in a detached task, newest wins (a generation counter): its answer is dropped when a newer request was made
//  or the file's centre changed meanwhile. A ring or spot is indexed again at every read of `readout`, so a new crystal, tolerance or
//  scale re-indexes everything without a refit.
//

import Foundation
import Observation
import ImagoCore
import DiffractoCore
import DiffractoScattering
import DiffractoGeometry
import DiffractoOrientation
import TEMCore

/// A phase of the person's library (#779), as the room uses it: its id, its name and its structure, with the structure's
/// fingerprint (an edited lattice is another fingerprint). The library itself is EMSuiteUI's; the room needs only these.
package nonisolated struct PhaseCrystal: Sendable, Equatable {
    package let id: String
    package let name: String
    package let structure: CrystalStructure
    package let fingerprint: String

    package init(id: String, name: String, structure: CrystalStructure) {
        self.id = id
        self.name = name
        self.structure = structure
        self.fingerprint = CrystalStructure.Snapshot(structure).fingerprint
    }
}

/// The crystal indexing is done against: a standard of the room, one opened from a CIF, or a phase of the library.
package nonisolated enum DiffractionCrystal: Sendable, Equatable {
    case preset(StandardCrystal)
    case cif(LoadedCrystal)
    case phase(PhaseCrystal)

    package var name: String {
        switch self {
        case .preset(let s): s.name
        case .cif(let c): c.displayName
        case .phase(let p): p.name
        }
    }
    package var structure: CrystalStructure {
        switch self {
        case .preset(let s): s.structure
        case .cif(let c): c.structure
        case .phase(let p): p.structure
        }
    }
    package var sha256: String? {
        if case .cif(let c) = self { return c.sha256 }
        return nil
    }
    /// The library phase's id, when the crystal is one.
    package var phaseID: String? {
        if case .phase(let p) = self { return p.id }
        return nil
    }
    /// The lattice in one line, as the kit holds it: "a 4.0782 Å" for a cubic cell, all six otherwise (#780: every result and
    /// export names the lattice it used). `ascii` writes "A" and "deg", as the CSV headers do.
    /// `locale`: the point (the default) for the exports, the door and the `ascii` file text; the reader's for the Phases list, where
    /// a decimal comma parts the lengths and the angles by semicolons, so "a 3,1355; b 3,1355" never reads as four numbers (#1039).
    package static func latticeText(_ cell: UnitCell, ascii: Bool = false, locale: Locale = UnitDisplay.point) -> String {
        let angstrom = ascii ? "A" : "Å", degree = ascii ? " deg" : "°"
        let mark = ascii ? UnitDisplay.point : locale
        func f(_ x: Double) -> String { UnitDisplay.fixed(x, places: 4, locale: mark) }
        func g(_ x: Double) -> String { UnitDisplay.fixed(x, places: 2, locale: mark) + degree }
        let cubic = abs(cell.a - cell.b) < 1e-6 && abs(cell.b - cell.c) < 1e-6
            && [cell.alphaDeg, cell.betaDeg, cell.gammaDeg].allSatisfy { abs($0 - 90) < 1e-6 }
        if cubic { return "a \(f(cell.a)) \(angstrom)" }
        let comma = mark.decimalSeparator == ","
        let item = comma ? "; " : ", ", group = comma ? " · " : "; "
        return "a \(f(cell.a))\(item)b \(f(cell.b))\(item)c \(f(cell.c)) \(angstrom)\(group)"
            + [cell.alphaDeg, cell.betaDeg, cell.gammaDeg].map(g).joined(separator: item)
    }

    /// The lattice this crystal computes with.
    package var lattice: String { Self.latticeText(structure.cell) }

    /// Where a library phase came from, for the exports: "phase mp-81, fingerprint …"; nil for a standard or a loose CIF.
    package var phaseText: String? {
        if case .phase(let p) = self { return "phase \(p.id), fingerprint \(p.fingerprint)" }
        return nil
    }

    /// What tells two crystals of the same name apart for the simulator's cache: the CIF's hash or the phase's fingerprint.
    package var identity: String {
        switch self {
        case .preset(let s): "preset|\(s.name)"
        case .cif(let c): "cif|\(c.sha256)"
        case .phase(let p): "phase|\(p.id)|\(p.fingerprint)"
        }
    }
}

/// A result of the room that the Output pane records (#1113), as the EBSD rooms record each run: a calibration on a standard's ring,
/// or Index's answer. The app writes the line (`DiffractionEventLine`).
package nonisolated enum DiffractionEvent: Sendable, Equatable {
    /// Calibrate on Ring set the scale: the standard and its family, the fitted ring's radius (px), Δq (Å⁻¹/px), and Δq_fit / Δq_file − 1
    /// in percent when the file has a reciprocal axis.
    case calibrated(standard: String, family: String, radius: Double, deltaQ: Double, versusFilePercent: Double?)
    /// Calibrate on Ring set no scale, in words.
    case calibrationRefused(String)
    /// Index answered (any verdict), with how many solutions the pattern cannot tell apart.
    case indexed(PatternIndexing.Outcome, solutions: Int)
}

@Observable
package final class DiffractionAnalysis {
    // The facts
    package private(set) var centre: DiffractionCentre?
    package private(set) var crystal: DiffractionCrystal = .preset(StandardCrystals.all[0])
    /// The standard a ring is calibrated on, and the index of its family in the list (the nearest few families).
    package private(set) var standard: StandardCrystal = StandardCrystals.all[0]
    package var familyIndex = 0
    package private(set) var kMax: Double = 3
    package var tolerancePercent: Double = 1
    package private(set) var ringCalibration: DiffractionCalibration?
    package private(set) var calibratedFamily: String?
    package var typedDeltaQ: Double?
    package var typedBeamKV: Double?
    package var pitchMM: Double?
    /// A Simulation document's camera length, mm (its Microscope section, #907): R in mm on the detector is λ L |g|.
    package private(set) var cameraLengthMM = DiffractionAnalysis.defaultCameraLengthMM
    package private(set) var rings: [MeasuredRing] = []
    package private(set) var spots: [MeasuredSpot] = []
    /// The ring or spot added last (a click, or a ring fit that landed): the room selects it. Selection itself is view state.
    package private(set) var lastAdded: UUID?
    package private(set) var isFitting = false
    /// Index is running (the toolbar's verb, #783).
    package private(set) var isIndexing = false
    /// Index's last answer for this pattern; nil before the first and after the crystal changed.
    package private(set) var indexOutcome: PatternIndexing.Outcome?
    package private(set) var failure: String?
    /// A CIF the kit refused, in its words.
    package private(set) var cifRefusal: String?
    /// Why the crystal has no list: a CIF refusal, else the kit's refusal to build the kinematic list at this k_max.
    package var crystalFailure: String? { cifRefusal ?? listResult().failure }
    /// The simulated spots of a typed zone axis over the pattern (#782): shown or not, the zone axis, its turn, the labels.
    package var simulation = ZoneAxisOverlay.Settings()
    /// Told of each calibration on a ring and each Index answer that lands (#1113); the app writes it as an Output line.
    @ObservationIgnored package var onEvent: (@MainActor (DiffractionEvent) -> Void)?

    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var fitTask: Task<Void, Never>?
    /// The centre each ring was fitted about, by id: Calibrate on Ring takes a ring already fitted only about the centre now (#1114).
    @ObservationIgnored private var ringCentres: [UUID: DiffractionCentre] = [:]
    @ObservationIgnored private var indexTask: Task<Void, Never>?
    @ObservationIgnored private var indexGeneration = 0
    /// The scales Index ran under (a ring's calibration, the typed Δq; the file's axis does not change): its measured |q| over |g|
    /// holds only while they stay (`indexIsStale`).
    private var indexScaleKey: IndexScaleKey?
    /// The spots Index read, by id (`indexSpotsChanged`).
    private var indexedSpots: [UUID] = []
    /// Index fits the scale within ±3 % (#787); off, it holds the room's scale (|q| over |g| at 1). Read when Index runs.
    package var fitScale = true
    /// Which of Index's solutions the overlay draws (0 the best; `PatternIndexing.solutions`).
    package private(set) var solutionIndex = 0
    /// The overlay's orientation was dragged, turned or flipped by hand since Index or a typed zone axis set it: the header names its
    /// nearest zone axis (`orientationLine`).
    package private(set) var isTurnedByHand = false
    private struct IndexScaleKey: Equatable {
        var ring: DiffractionCalibration?
        var typed: Double?
        // Written out: Periphery reads a synthesized == as never reading the fields.
        static func == (a: IndexScaleKey, b: IndexScaleKey) -> Bool { a.ring == b.ring && a.typed == b.typed }
    }
    private var scaleKey: IndexScaleKey { IndexScaleKey(ring: ringCalibration, typed: typedDeltaQ) }
    @ObservationIgnored private var listCache: (key: String, list: KinematicReflectionList?, failure: String?)?
    @ObservationIgnored private var familiesCache: [String: [(name: String, d: Double, family: ReflectionFamily)]] = [:]
    @ObservationIgnored private var readoutCache: (key: ReadoutKey, rows: [DiffractionReadoutRow])?
    @ObservationIgnored private var simulatorCache: (key: String, simulator: SpotPatternSimulator?, failure: String?)?
    @ObservationIgnored private var simulationCache: (key: SimulationKey, result: SimulatedSpots)?
    @ObservationIgnored private var addedCache: (key: String, spots: [PatternIndexing.AddedSpot])?
    /// The beam energy Index's answer was found at (V).
    private var indexVolts: Double?
    @ObservationIgnored private var boundSize: (Int, Int)?

    package init() {}

    // MARK: Binding to the image

    /// Sets the starting centre and k_max from the image the first time it is seen (and again for a different size).
    package func bind(_ image: CalibratedImage) {
        guard boundSize?.0 != image.width || boundSize?.1 != image.height else { return }
        boundSize = (image.width, image.height)
        centre = .imageCentre(width: image.width, height: image.height)
        dropFitInFlight()
        let dq = fileDeltaQ(image) ?? 0.0125
        setKMax(min(4, max(0.5, (Double(min(image.width, image.height)) / 2 * dq * 10).rounded() / 10)))
    }

    package func fileDeltaQ(_ image: CalibratedImage) -> Double? { DiffractionCalibration.fileDeltaQ(image.x) }

    // MARK: Calibration

    /// The scale in use: a ring fit on a standard, else the file's reciprocal axis, else a typed Δq; nil with none.
    package func calibration(for image: CalibratedImage) -> DiffractionCalibration? {
        if let ringCalibration { return ringCalibration }
        if let dq = fileDeltaQ(image) { return DiffractionCalibration(source: .fileAxis, deltaQ: dq, ring: nil) }
        if let dq = typedDeltaQ, dq > 0 { return DiffractionCalibration(source: .typed, deltaQ: dq, ring: nil) }
        return nil
    }

    /// Δq_fit / Δq_file − 1 in percent, when both exist.
    package func fitVersusFilePercent(for image: CalibratedImage) -> Double? {
        guard let ring = ringCalibration, let file = fileDeltaQ(image) else { return nil }
        let v = RingScale.fitVersusFile(fitDeltaQ: ring.deltaQ, fileDeltaQ: file)
        return v.isFinite ? 100 * v : nil
    }

    /// The beam energy in volts: the file's, else the typed kV.
    package func volts(for image: CalibratedImage) -> Double? {
        if let v = image.voltage, v > 0 { return v }
        if let kv = typedBeamKV, kv > 0 { return kv * 1000 }
        return nil
    }

    package var ringCalibrationExists: Bool { ringCalibration != nil }

    package func clearCalibration() { ringCalibration = nil; calibratedFamily = nil }

    // MARK: Centre

    package func setCentre(row: Double, column: Double) {
        guard row.isFinite, column.isFinite else { return }
        centre = DiffractionCentre(row: row, column: column, source: .typed)
        dropFitInFlight()
    }

    /// Takes the fitted ring's centre as the pattern's (offered, never applied by itself).
    package func useCentre(ofRing id: UUID) {
        guard let fit = rings.first(where: { $0.id == id })?.fit?.fit else { return }
        centre = DiffractionCentre(row: fit.centerQX, column: fit.centerQY, source: .ring)
        dropFitInFlight()
    }

    /// A ring fit measures its radius about the centre it started with: once the centre moves its answer is about the wrong point, so
    /// it must not land and set the scale (macEM#610). The fit is cancelled and its generation retired.
    private func dropFitInFlight() {
        guard isFitting || isIndexing else { return }
        stop()
    }

    // MARK: Crystal

    package func setCrystal(_ new: DiffractionCrystal) {
        if new != crystal { dropIndex() }
        crystal = new
        cifRefusal = nil
        if case .preset(let s) = new { standard = s }
    }

    package func setStandard(_ new: StandardCrystal) {
        standard = new
        familyIndex = 0
        if case .preset = crystal, crystal != .preset(new) { dropIndex(); crystal = .preset(new) }
    }

    package func crystalRefused(_ words: String) { cifRefusal = words }

    /// Another crystal: Index's answer and orientation were the old crystal's.
    private func dropIndex() {
        indexTask?.cancel(); indexTask = nil
        indexGeneration += 1
        isIndexing = false
        indexOutcome = nil
        simulation.indexed = nil
        simulation.scale = 1
        solutionIndex = 0
        isTurnedByHand = false
    }

    /// k_max in Å⁻¹, kept in the kit's range.
    package func setKMax(_ value: Double) {
        guard value.isFinite else { return }
        kMax = min(max(value, 0.2), 4)
    }

    package func setTolerance(percent: Double) {
        guard percent.isFinite else { return }
        tolerancePercent = max(percent, 0.01)
    }

    /// The kinematic list of the crystal at the current k_max and why there is none. Cached by crystal and k_max; it writes no observed state, so a
    /// view body may call it (the build runs on the first call after the crystal or k_max changed).
    private func listResult() -> (list: KinematicReflectionList?, failure: String?) {
        let key = "\(crystal.identity)|\(kMax)"
        if let listCache, listCache.key == key { return (listCache.list, listCache.failure) }
        let built: (list: KinematicReflectionList?, failure: String?)
        do { built = (try DiffractionCompute.list(of: crystal.structure, kMax: kMax), nil) }
        catch { built = (nil, error.localizedDescription) }
        listCache = (key, built.list, built.failure)
        return built
    }

    package func list() -> KinematicReflectionList? { listResult().list }

    /// The standard's first families (the ones a ring is picked from): name, d. Cached by standard and k_max.
    package func standardFamilies(of other: StandardCrystal? = nil) -> [(name: String, d: Double, family: ReflectionFamily)] {
        let standard = other ?? self.standard
        let reach = max(kMax, 2.5)
        let key = "\(standard.name)|\(reach)"
        if let hit = familiesCache[key] { return hit }
        guard let list = try? DiffractionCompute.list(of: standard.structure, kMax: reach) else { return [] }
        let families = list.families.prefix(6).map { (name: DiffractionCompute.familyName($0.family), d: $0.family.d, family: $0.family) }
        familiesCache[key] = families
        return families
    }

    // MARK: Rings

    /// Fits the ring in the annulus; with `calibrate`, also calibrates against that family of the standard. Newest wins. To calibrate,
    /// a ring already fitted in this very annulus about this centre is taken as it is (#1114): no second fit and no second row, and nil
    /// is returned, as nothing runs.
    @discardableResult
    package func fitRing(image: CalibratedImage, inner: Double, outer: Double, calibrateOn family: ReflectionFamily? = nil) -> Task<Void, Never>? {
        guard let centre, inner.isFinite, outer.isFinite, outer > inner, inner > 0 else { return nil }
        let volts = volts(for: image), pitch = pitchMM, fileQ = fileDeltaQ(image)
        let standardName = standard.name
        if let family, let fitted = fittedRing(inner: inner, outer: outer, centre: centre), let fit = fitted.fit {
            stopFit()
            failure = nil
            let answer = Self.ringScale(of: fit, family: family, standard: standardName, volts: volts, pitch: pitch)
            if let scale = answer.calibration { take(scale, family: family, fromRing: fitted.id) }
            if let refusal = answer.refusal { failure = refusal }
            onEvent?(calibrationEvent(standard: standardName, refusal: answer.refusal, fileDeltaQ: fileQ))
            return nil
        }
        generation += 1
        let gen = generation
        fitTask?.cancel()
        failure = nil
        isFitting = true
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            // A uint8 or uint16 image's Float32 copy is made here, off the main actor (#928).
            let pattern = DiffractionCompute.pattern(of: image)
            let result = DiffractionCompute.fitRing(pattern: pattern, centre: centre, inner: inner, outer: outer, isCancelled: { Task.isCancelled })
            if Task.isCancelled { return }
            await self?.landRing(result, inner: inner, outer: outer, centre: centre, family: family, standard: standardName, volts: volts,
                                 pitch: pitch, fileDeltaQ: fileQ, generation: gen)
        }
        fitTask = task
        return task
    }

    private func landRing(_ result: (fit: RingRadiusFit?, refusal: String?), inner: Double, outer: Double, centre: DiffractionCentre,
                          family: ReflectionFamily?, standard name: String, volts: Double?, pitch: Double?, fileDeltaQ: Double?,
                          generation gen: Int) {
        guard gen == generation else { return }
        isFitting = false
        var refusal = result.refusal
        var scale: DiffractionCalibration?
        if let family, let fit = result.fit, refusal == nil {
            let answer = Self.ringScale(of: fit, family: family, standard: name, volts: volts, pitch: pitch)
            scale = answer.calibration
            refusal = answer.refusal
        } else if family != nil, refusal == nil, result.fit == nil {
            refusal = "no ring was fitted"
        }
        let ring = MeasuredRing(innerRadius: inner, outerRadius: outer, fit: result.fit, refusal: refusal, isCalibrating: false)
        rings.append(ring)
        ringCentres[ring.id] = centre
        if let family, let scale { take(scale, family: family, fromRing: ring.id) }
        lastAdded = ring.id
        if let refusal { failure = refusal }
        if family != nil { onEvent?(calibrationEvent(standard: name, refusal: refusal, fileDeltaQ: fileDeltaQ)) }
    }

    /// The ring fitted last in exactly this annulus about this centre, usable and refusing nothing (#1114); nil when there is none.
    private func fittedRing(inner: Double, outer: Double, centre: DiffractionCentre) -> MeasuredRing? {
        rings.last { ring in
            ring.innerRadius == inner && ring.outerRadius == outer && ring.refusal == nil && ring.fit?.isUsable == true
                && ringCentres[ring.id] == centre
        }
    }

    /// The scale a fitted ring gives against the spacing of `family` of the standard `name`, by the kit, or why it gives none.
    private static func ringScale(of fit: RingRadiusFit, family: ReflectionFamily, standard name: String, volts: Double?,
                                  pitch: Double?) -> (calibration: DiffractionCalibration?, refusal: String?) {
        do {
            let calibrated = try DiffractionCompute.calibrate(fit, d: family.d, volts: volts, pitchMM: pitch)
            guard let ring = calibrated.calibration else {
                return (nil, calibrated.refusals.first?.reason ?? "the ring could not calibrate the scale")
            }
            return (DiffractionCalibration(source: .ringFit(standard: name, family: DiffractionCompute.familyName(family)), deltaQ: ring.deltaQ,
                                           ring: ring), nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    /// The scale a ring set: the room's calibration, and that ring alone marked as the one that set it.
    private func take(_ calibration: DiffractionCalibration, family: ReflectionFamily, fromRing id: UUID) {
        ringCalibration = calibration
        calibratedFamily = DiffractionCompute.familyName(family)
        for i in rings.indices { rings[i].isCalibrating = rings[i].id == id }
    }

    /// What a Calibrate on Ring that landed tells the Output pane (#1113): the scale it set, else why it set none.
    private func calibrationEvent(standard name: String, refusal: String?, fileDeltaQ: Double?) -> DiffractionEvent {
        guard refusal == nil, let calibration = ringCalibration, let ring = calibration.ring, let family = calibratedFamily else {
            return .calibrationRefused(refusal ?? "the ring could not calibrate the scale")
        }
        let versus = fileDeltaQ.map { 100 * RingScale.fitVersusFile(fitDeltaQ: calibration.deltaQ, fileDeltaQ: $0) }
        return .calibrated(standard: name, family: family, radius: ring.radius, deltaQ: calibration.deltaQ,
                           versusFilePercent: versus.flatMap { $0.isFinite ? $0 : nil })
    }

    /// Stop (⌘.): the ring fit and Index in flight.
    package func stop() {
        stopFit()
        indexTask?.cancel(); indexTask = nil
        indexGeneration += 1
        isIndexing = false
    }

    /// The ring fit in flight only (a removal or its undo: its ring would land on marks it was not asked for).
    private func stopFit() {
        fitTask?.cancel(); fitTask = nil
        generation += 1
        isFitting = false
    }

    // MARK: Index

    /// Why Index cannot run on this image now, in words; nil when it can.
    package func indexBlocker(image: CalibratedImage) -> String? {
        if centre == nil { return "Index needs the pattern's centre" }
        if calibration(for: image) == nil { return "Index needs a scale: calibrate on a standard's ring, or type Δq" }
        if volts(for: image) == nil { return "Index needs the beam energy: type it under Calibration" }
        if let why = crystalFailure { return why }
        return nil
    }

    /// Index (#783), off the main actor: with no spot marked, the kit finds the spots and they become ordinary marks (#784), which
    /// the user can remove or add to before Index runs again; with spots marked, Index reads those. Found spots carry the kit's
    /// intensities and give the crystal's full orientation; a clicked spot among them gives the zone axis and the turn only
    /// (`PatternIndexing.index(marks:)`). The answer lands in `indexOutcome`, and a found orientation becomes the simulated spots'
    /// (`simulation.indexed`, drawn at its fitted scale). A newer Index, Stop, a centre move, or a scale or spot changed while it
    /// runs drops the answer of the one in flight.
    @discardableResult
    package func index(image: CalibratedImage) -> Task<Void, Never>? {
        guard indexBlocker(image: image) == nil, let centre, let calibration = calibration(for: image), let volts = volts(for: image)
        else { return nil }
        indexTask?.cancel()
        indexGeneration += 1
        let gen = indexGeneration
        isIndexing = true
        failure = nil
        let started = scaleKey, startedSpots = spots
        let marked = spots.compactMap { s in
            s.row.flatMap { r in s.column.map { c in PatternIndexing.Mark(id: s.id, row: r, column: c, intensity: s.intensity) } }
        }
        let structure = crystal.structure, phase = crystal.name
        let fit = fitScale
        let key = "\(crystal.identity)|\(volts)" + (fit ? "" : "|fixed scale")
        let shortest = list()?.families.first.map { 1 / $0.family.d } ?? 0.2
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            // Quality bar: Index answers for one 2048² pattern within 2 s on the reference Mac (#797, docs/performance.md).
            let interval = Signposts.begin("diffraction.index"); defer { Signposts.end(interval) }
            let outcome: PatternIndexing.Outcome
            var found: [PatternIndexing.Mark]?
            do {
                var marks = marked
                if marks.isEmpty {
                    // A uint8 or uint16 image's Float32 copy is made here, off the main actor (#928).
                    let pattern = DiffractionCompute.pattern(of: image)
                    let located = try PatternIndexing.findSpots(pattern: pattern, centre: centre, shortestG: shortest, calibration: calibration)
                    marks = located.map { PatternIndexing.Mark(id: UUID(), row: $0.row, column: $0.column, intensity: $0.intensity) }
                    found = marks
                }
                if Task.isCancelled { return }
                let indexer = try PatternIndexerCache.shared.indexer(key: key) {
                    try PatternOrientation(structure: structure, volts: volts, kMax: PatternIndexing.reach,
                                           solverSettings: PatternIndexing.solverSettings(fitScale: fit))
                }
                if Task.isCancelled { return }
                outcome = PatternIndexing.index(marks: marks, centre: centre, calibration: calibration, indexer: indexer, phase: phase)
            } catch {
                let words = String(describing: error)
                outcome = PatternIndexing.Outcome(phase: phase, verdict: .notFound(words), spots: [], explained: 0, indexed: 0,
                                                  orientation: nil, alternatives: [], zoneAxis: nil, zoneAxisAngle: nil, scale: nil,
                                                  misfitPercent: nil)
            }
            if Task.isCancelled { return }
            await self?.landIndex(outcome, found: found, generation: gen, scale: started, spots: startedSpots, volts: volts)
        }
        indexTask = task
        return task
    }

    private func landIndex(_ outcome: PatternIndexing.Outcome, found: [PatternIndexing.Mark]?, generation gen: Int, scale started: IndexScaleKey,
                           spots startedSpots: [MeasuredSpot], volts: Double) {
        guard gen == indexGeneration else { return }
        isIndexing = false
        indexTask = nil
        // The scale or the spots changed while Index ran (a ring fit landed, Δq typed, a spot clicked or removed): its answer was
        // measured under the old ones.
        guard started == scaleKey, startedSpots == spots else { return }
        if let found {
            // The found spots become ordinary marks, each at the kit's centre, with its intensity.
            spots = found.map { MeasuredSpot(id: $0.id, clickRow: $0.row, clickColumn: $0.column, row: $0.row, column: $0.column, radius: nil,
                                             refusal: nil, intensity: $0.intensity) }
        }
        indexOutcome = outcome
        indexVolts = volts
        indexScaleKey = started
        indexedSpots = spots.map(\.id)
        solutionIndex = 0
        onEvent?(.indexed(outcome, solutions: solutions.count))
        guard let orientation = outcome.orientation else { return }
        isTurnedByHand = false
        simulation.indexed = orientation
        simulation.scale = outcome.scale ?? 1
        if let uvw = outcome.zoneAxis { simulation.zoneAxis = uvw }
        simulation.isShown = true
    }

    /// The scale changed since Index answered: its fitted |q| over |g|, its misfit and its verdict were measured under the old
    /// one. The overlay draws its orientation at |g| until Index runs again; the header says so.
    package var indexIsStale: Bool { indexOutcome != nil && indexScaleKey != scaleKey }

    /// A spot was removed or added since Index answered (#784): its answer was the old spots'. The header says so; the overlay keeps
    /// the orientation until Index runs again.
    package var indexSpotsChanged: Bool { indexOutcome != nil && indexedSpots != spots.map(\.id) }

    /// The Spots table's rows (#785): Index's spots still marked, numbered as the readout numbers them, R in mm with the camera's
    /// pixel pitch; [] before an answer.
    package var indexSpotRows: [PatternIndexing.SpotRow] {
        guard let outcome = indexOutcome else { return [] }
        let numbers = Dictionary(uniqueKeysWithValues: spots.enumerated().map { ($1.id, $0 + 1) })
        return PatternIndexing.rows(outcome, numbers: numbers, added: addedSpots(outcome), cell: crystal.structure.cell,
                                    pitchMM: pitchMM)
    }

    /// The spots double diffraction adds at Index's best orientation, with Double diffraction on (#786): the Spots table names a
    /// spot Index left unexplained that sits on one. Kept while the crystal, the beam, σ and the orientation stay.
    private func addedSpots(_ outcome: PatternIndexing.Outcome) -> [PatternIndexing.AddedSpot] {
        guard simulation.doubleDiffraction, let orientation = outcome.orientation, let volts = indexVolts else { return [] }
        let key = "\(crystal.name)|\(crystal.sha256 ?? "")|\(volts)|\(simulation.excitationError)|\(orientation.orixQuaternion)"
        if let addedCache, addedCache.key == key { return addedCache.spots }
        let added = (try? PatternIndexing.addedSpots(structure: crystal.structure, orientation: orientation, volts: volts,
                                                     sigma: simulation.excitationError)) ?? []
        addedCache = (key, added)
        return added
    }

    /// The Spots CSV (#785): the table's columns, its rows by number, under the file and Index's line.
    package func spotsExportText(image: CalibratedImage) -> String {
        PatternIndexing.csv(rows: indexSpotRows, fileName: image.fileName, line: indexLine ?? "")
    }

    // MARK: A Simulation document (#907)

    /// The camera length a Simulation document starts at, mm: the middle of a TEM's selected-area range (about 100 to 2 000 mm).
    package static let defaultCameraLengthMM = 500.0
    /// The camera lengths the Microscope section takes, mm.
    package static let cameraLengthRangeMM = 1.0 ... 100_000.0

    /// Sets the camera length; a value that is not finite or outside `cameraLengthRangeMM` changes nothing. Returns whether it was kept.
    @discardableResult
    package func setCameraLength(mm: Double?) -> Bool {
        guard let mm, mm.isFinite, Self.cameraLengthRangeMM.contains(mm) else { return false }
        cameraLengthMM = mm
        return true
    }

    /// A Simulation document's Spots table (#907): the simulated spots drawn, strongest first, with R in mm at the camera length;
    /// [] while the spots are off or cannot be drawn.
    package func simulatedSpotRows(image: CalibratedImage) -> [PatternIndexing.SpotRow] {
        guard case .success(let drawn) = simulatedSpots(image: image), let centre, let calibration = calibration(for: image),
              let volts = volts(for: image) else { return [] }
        return PatternIndexing.simulatedRows(drawn, centreRow: centre.row, centreColumn: centre.column, deltaQ: calibration.deltaQ,
                                             volts: volts, cameraLengthMM: cameraLengthMM, phase: crystal.name)
    }

    /// A Simulation document's Spots CSV: the table's columns and rows under the file and the settings they were simulated at.
    package func simulatedSpotsExportText(image: CalibratedImage) -> String {
        // A file's numbers are written locale-free (`%g`), whatever the reader's decimal mark.
        func g(_ v: Double) -> String { String(format: "%.6g", v) }
        let kV = volts(for: image).map { "\(g($0 / 1000)) kV" } ?? "no beam energy"
        let line = "\(crystal.name) \(ZoneAxisText.text(simulation.zoneAxis)), turn \(g(simulation.inPlaneDegrees))°, \(kV), L \(g(cameraLengthMM)) mm"
        return PatternIndexing.csv(rows: simulatedSpotRows(image: image), fileName: image.fileName, line: line, lineName: "simulation")
    }

    /// The header's line for Index's answer, with what changed since: a scale (a ring calibrated, Δq typed) or the spots. The CSV
    /// and the door read it with a decimal point; the header row draws `indexHeaderLine(locale:)` in the reader's (#1039).
    package var indexLine: String? { indexHeaderLine(locale: UnitDisplay.point) }

    /// `indexLine` with its numbers in `locale`.
    package func indexHeaderLine(locale: Locale) -> String? { indexHeaderLevels(locale: locale).first }

    /// The header's line at each length, longest first (#1113): the whole line, then without the count of spots explained and the
    /// solution's number, so a narrow header drops those whole and keeps the place, the verdict's words, the misfit and what changed
    /// since. Empty before Index answered.
    package func indexHeaderLevels(locale: Locale) -> [String] {
        guard let outcome = indexOutcome else { return [] }
        let n = solutions.count
        var since = ""
        if indexIsStale { since += " · the scale changed since: Index again" }
        if indexSpotsChanged { since += " · the spots changed since: Index again" }
        let full = PatternIndexing.header(outcome, locale: locale) + (n > 1 ? " · solution \(solutionIndex + 1) of \(n)" : "") + since
        let short = PatternIndexing.header(outcome, locale: locale, spotCount: false) + since
        return short == full ? [full] : [full, short]
    }

    /// The zone axis typed: the simulated spots are this zone axis's, no longer Index's orientation.
    package func setZoneAxis(_ uvw: SIMD3<Int>) {
        simulation.zoneAxis = uvw
        simulation.indexed = nil
        simulation.scale = 1
        isTurnedByHand = false
    }

    // MARK: Solutions, Flip and turning by hand (#787)

    /// Index's solutions the Index section steps through: the best, then those the pattern cannot tell from it (at most five).
    package var solutions: [CrystalOrientation] { indexOutcome.map(PatternIndexing.solutions) ?? [] }

    /// Draws Index's solution `index` (0 the best) at Index's fitted scale; out of range does nothing.
    package func selectSolution(_ index: Int) {
        let all = solutions
        guard all.indices.contains(index) else { return }
        solutionIndex = index
        isTurnedByHand = false
        simulation.indexed = all[index]
        simulation.scale = indexOutcome?.scale ?? 1
        if let near = all[index].nearestZoneAxis(cell: crystal.structure.cell) { simulation.zoneAxis = near.uvw }
        simulation.isShown = true
    }

    /// The Tilt tool's keyboard twin and the door's tilt (#787): the drawn orientation tilted as a drag of `down` degrees down the
    /// rows and `across` degrees along the columns would tilt it (`ZoneAxisOverlay.tilted`). False, changing nothing, with nothing drawn.
    @discardableResult
    package func tilt(down: Double, across: Double) -> Bool {
        guard let base = drawnOrientation else { return false }
        turnByHand(to: ZoneAxisOverlay.tilted(base, drag: SIMD2(down, across) / ZoneAxisOverlay.degreesPerPoint))
        return true
    }

    /// The orientation the overlay draws now: Index's (or a solution, or a hand-turned one), else the typed zone axis and turn.
    package var drawnOrientation: CrystalOrientation? { try? simulation.orientation(cell: crystal.structure.cell) }

    /// The overlay drawn at `orientation`, set by hand (a drag, ⌥ drag or Flip): the scale stays, the zone axis field shows the nearest.
    package func turnByHand(to orientation: CrystalOrientation) {
        simulation.indexed = orientation
        isTurnedByHand = true
        if let near = orientation.nearestZoneAxis(cell: crystal.structure.cell) { simulation.zoneAxis = near.uvw }
        simulation.isShown = true
    }

    /// Flip: the drawn orientation turned 180° about the beam (the pattern's two-fold look-alike a centrosymmetric pattern cannot tell).
    package func flip() {
        guard let o = drawnOrientation else { return }
        turnByHand(to: o.rotatedInPlane(by: .pi))
    }

    /// The header's line for the drawn orientation once it was turned by hand, or while no Index answer is shown: "Al · 2.1° from
    /// [001]", "Al [001]" within 0.5°; nil while the overlay is off.
    package var orientationLine: String? { orientationHeaderLine(locale: UnitDisplay.point) }

    /// `orientationLine` with its angle in `locale`: the reader's in the header row, the point (the door's) by default (#1039).
    package func orientationHeaderLine(locale: Locale) -> String? {
        guard simulation.isShown, isTurnedByHand || indexOutcome == nil, let o = drawnOrientation,
              let near = o.nearestZoneAxis(cell: crystal.structure.cell) else { return nil }
        return PatternIndexing.place(phase: crystal.name, zoneAxis: near.uvw, angle: near.angle, locale: locale)
            + (isTurnedByHand ? " · set by hand" : "")
    }

    /// The turn typed (degrees): as `setZoneAxis`, the typed zone axis turned by it.
    package func setTurn(degrees: Double) {
        guard degrees.isFinite else { return }
        simulation.inPlaneDegrees = degrees.truncatingRemainder(dividingBy: 360)
        simulation.indexed = nil
        simulation.scale = 1
        isTurnedByHand = false
    }

    /// The excitation error typed (σ, Å⁻¹, #786): the simulated pattern keeps spots with |s| up to three times it. A value that is not a
    /// finite number in 0.001...1 is not taken (false), and the last one stays.
    @discardableResult
    package func setExcitationError(_ sigma: Double) -> Bool {
        guard sigma.isFinite, sigma >= 0.001, sigma <= 1 else { return false }
        simulation.excitationError = sigma
        return true
    }

    // MARK: Spots

    /// A click on the pattern: the centre is refined (the kit's `PatternSpot.refine`), and the spot is listed with its radius and indexing.
    package func addSpot(image: CalibratedImage, row: Double, column: Double) {
        let refined = DiffractionCompute.refineSpot(in: image, row: row, column: column)
        let spot: MeasuredSpot
        if let refined {
            spot = MeasuredSpot(clickRow: row, clickColumn: column, row: refined.row, column: refined.column, radius: nil, refusal: nil)
        } else {
            spot = MeasuredSpot(clickRow: row, clickColumn: column, row: nil, column: nil, radius: nil, refusal: "no signal near the click")
        }
        spots.append(spot)
        lastAdded = spot.id
    }

    package func remove(_ id: UUID) {
        rings.removeAll { $0.id == id }
        spots.removeAll { $0.id == id }
        if ringCalibration != nil, !rings.contains(where: \.isCalibrating) { clearCalibration() }
    }

    /// Every spot, the rings and their scale kept (#784): Index then finds the spots again, with the intensities a clicked spot lacks.
    package func removeSpots() {
        spots = []
        if let id = lastAdded, !rings.contains(where: { $0.id == id }) { lastAdded = nil }
    }

    package func removeAll() {
        stopFit()
        rings = []; spots = []; lastAdded = nil; clearCalibration(); failure = nil
    }

    /// The rings, the spots and the scale a ring set, as one value: what Edit > Undo of a removal puts back (#325). A typed scale, the
    /// centre and the crystal are not marks and are never touched by it.
    package nonisolated struct Marks: Equatable, Sendable {
        package var rings: [MeasuredRing]
        package var spots: [MeasuredSpot]
        package var ringCalibration: DiffractionCalibration?
        package var calibratedFamily: String?
    }

    package var marks: Marks {
        Marks(rings: rings, spots: spots, ringCalibration: ringCalibration, calibratedFamily: calibratedFamily)
    }

    /// Puts `marks` back as they were, ids and the ring's scale with them; a fit still running is stopped (its ring would land on marks it
    /// was not asked for).
    package func restore(_ marks: Marks) {
        stopFit()
        rings = marks.rings; spots = marks.spots
        ringCalibration = marks.ringCalibration; calibratedFamily = marks.calibratedFamily
        lastAdded = nil; failure = nil
    }

    // MARK: The simulated spots

    /// The overlay's spots, strongest first, or why there are none, in words.
    package typealias SimulatedSpots = Result<[ZoneAxisOverlay.Spot], SimulationAbsence>

    package nonisolated struct SimulationAbsence: Error, Equatable, Sendable {
        package let sentence: String
    }

    private struct SimulationKey: Equatable {
        var settings: ZoneAxisOverlay.Settings
        var crystal: DiffractionCrystal
        var centre: DiffractionCentre?
        var calibration: DiffractionCalibration?
        var volts: Double?
        var width: Int
        var height: Int
        var dynamical: DynamicalBeams?

        // Written out: Periphery reads a synthesized == as never reading the fields.
        static func == (a: SimulationKey, b: SimulationKey) -> Bool {
            a.settings == b.settings && a.crystal == b.crystal && a.centre == b.centre && a.calibration == b.calibration
                && a.volts == b.volts && a.width == b.width && a.height == b.height && a.dynamical == b.dynamical
        }
    }

    /// The simulated spots of `simulation`'s zone axis on this image: DiffractoKit's `SpotPatternSimulator` of the crystal at the
    /// beam energy, placed by the scale and centre in use (`ZoneAxisOverlay`). Made again whenever anything it reads changed (the
    /// zone axis, the turn, the crystal, the centre, the scale, the beam), else the last answer; nil while the overlay is off. It
    /// writes no observed state, so a view body may call it. With `dynamical` (a Simulation document's Dynamical switch, #911) the
    /// spots are its beams at its thickness, placed the same way.
    package func simulatedSpots(image: CalibratedImage, dynamical: DynamicalBeams? = nil) -> SimulatedSpots? {
        guard simulation.isShown else { return nil }
        let calibration = calibration(for: image)
        let volts = volts(for: image)
        var settings = simulation
        if indexIsStale { settings.scale = 1 }
        let key = SimulationKey(settings: settings, crystal: crystal, centre: centre, calibration: calibration, volts: volts,
                                width: image.width, height: image.height, dynamical: dynamical)
        if let simulationCache, simulationCache.key == key { return simulationCache.result }
        // Quality bar: a crystal turn redraws 500 reflections and the crystal view within one frame (#797, docs/performance.md).
        let interval = Signposts.begin("diffraction.spots"); defer { Signposts.end(interval) }
        let result = makeSimulatedSpots(settings: settings, calibration: calibration, volts: volts, width: image.width, height: image.height,
                                        dynamical: dynamical)
        simulationCache = (key, result)
        return result
    }

    private func makeSimulatedSpots(settings: ZoneAxisOverlay.Settings, calibration: DiffractionCalibration?, volts: Double?, width: Int,
                                    height: Int, dynamical: DynamicalBeams?) -> SimulatedSpots {
        guard let centre else { return .failure(SimulationAbsence(sentence: "No centre yet")) }
        guard let calibration, calibration.deltaQ.isFinite, calibration.deltaQ > 0 else {
            return .failure(SimulationAbsence(sentence: "Needs a scale: calibrate on a standard's ring, or type Δq"))
        }
        guard let volts else { return .failure(SimulationAbsence(sentence: "Needs the beam energy: type it under Calibration")) }
        // The simulator reaches the image's farthest corner, to at most the kit's k_max cap (`ReflectionList.maximumKMax`, 4 Å⁻¹,
        // d 0.25 Å: past it the kit refuses the whole list, so a wide pattern drew no spot at all), and is kept while the crystal and
        // the reach (to 0.1 Å⁻¹) stay.
        let reach = min(ReflectionList.maximumKMax, max(0.2, (ZoneAxisOverlay.reach(width: width, height: height, centre: centre, deltaQ: calibration.deltaQ) * 10).rounded(.up) / 10))
        let simulatorKey = "\(crystal.identity)|\(reach)"
        if simulatorCache?.key != simulatorKey {
            do { simulatorCache = (simulatorKey, try SpotPatternSimulator(structure: crystal.structure, kMax: reach), nil) }
            catch { simulatorCache = (simulatorKey, nil, error.localizedDescription) }
        }
        guard let simulator = simulatorCache?.simulator else {
            return .failure(SimulationAbsence(sentence: simulatorCache?.failure ?? "The crystal has no reflections"))
        }
        do {
            let spots = try ZoneAxisOverlay.spots(simulator: simulator, settings: settings, volts: volts, calibration: calibration,
                                                  centre: centre, width: width, height: height, dynamical: dynamical)
            return spots.isEmpty ? .failure(SimulationAbsence(sentence: "No simulated spot lands on this pattern")) : .success(spots)
        } catch {
            return .failure(SimulationAbsence(sentence: String(describing: error)))
        }
    }

    // MARK: The readout

    /// Everything the rows are made from. The rows are made again only when one of these differs from the last time, so a render the results did
    /// not cause (a zoom, a hover, a selection) costs a comparison and no indexing.
    private struct ReadoutKey: Equatable {
        var centre: DiffractionCentre?
        var crystal: DiffractionCrystal
        var kMax: Double
        var tolerancePercent: Double
        var ringCalibration: DiffractionCalibration?
        var typedDeltaQ: Double?
        var typedBeamKV: Double?
        var pitchMM: Double?
        var rings: [MeasuredRing]
        var spots: [MeasuredSpot]
        var fileName: String
        var width: Int
        var height: Int
        var voltage: Double?
        var axis: AxisCalibration?
    }

    /// Every ring and spot as a row, indexed against the crystal now (the last answer again while nothing it depends on changed).
    package func readout(image: CalibratedImage) -> [DiffractionReadoutRow] {
        let key = ReadoutKey(centre: centre, crystal: crystal, kMax: kMax, tolerancePercent: tolerancePercent, ringCalibration: ringCalibration,
                             typedDeltaQ: typedDeltaQ, typedBeamKV: typedBeamKV, pitchMM: pitchMM, rings: rings, spots: spots,
                             fileName: image.fileName, width: image.width, height: image.height, voltage: image.voltage, axis: image.x)
        if let readoutCache, readoutCache.key == key { return readoutCache.rows }
        let rows = makeReadout(image: image)
        readoutCache = (key, rows)
        return rows
    }

    private func makeReadout(image: CalibratedImage) -> [DiffractionReadoutRow] {
        let calibration = calibration(for: image)
        let list = list()
        let calibratingEllipse = rings.first(where: \.isCalibrating)?.ellipse
        var out: [DiffractionReadoutRow] = []
        func row(id: UUID, kind: DiffractionReadoutRow.Kind, number: Int, radius: Double?, calibrating: Bool, refusal: String?) -> DiffractionReadoutRow {
            guard let radius else {
                return DiffractionReadoutRow(id: id, kind: kind, number: number, radiusPx: nil, q: nil, d: nil, family: nil, dListed: nil,
                                             deltaPercent: nil, oddsText: nil, verdict: refusal ?? "no radius", validation: RingIndexing.validation)
            }
            guard let calibration else {
                return DiffractionReadoutRow(id: id, kind: kind, number: number, radiusPx: radius, q: nil, d: nil, family: nil, dListed: nil,
                                             deltaPercent: nil, oddsText: nil, verdict: "no scale yet: calibrate a ring or type Δq",
                                             validation: RingIndexing.validation)
            }
            let q = calibration.q(radius: radius)
            guard q.isFinite, q > 0 else {
                return DiffractionReadoutRow(id: id, kind: kind, number: number, radiusPx: radius, q: nil, d: nil, family: nil, dListed: nil,
                                             deltaPercent: nil, oddsText: nil, verdict: "radius outside the scale", validation: RingIndexing.validation)
            }
            guard let list else {
                return DiffractionReadoutRow(id: id, kind: kind, number: number, radiusPx: radius, q: q, d: 1 / q, family: nil, dListed: nil,
                                             deltaPercent: nil, oddsText: nil, verdict: crystalFailure ?? "no crystal list", validation: RingIndexing.validation)
            }
            let indexing = IndexingDisplay.index(q: q, tolerancePercent: tolerancePercent, in: list)
            return DiffractionReadoutRow(id: id, kind: kind, number: number, radiusPx: radius, q: q, d: 1 / q,
                                         family: indexing.family.map { DiffractionCompute.familyName($0) }, dListed: indexing.dListed,
                                         deltaPercent: indexing.deltaPercent, oddsText: indexing.assignment == nil ? nil : indexing.oddsText,
                                         verdict: indexing.verdict, validation: indexing.validation, isCalibrating: calibrating,
                                         listedIntensity: indexing.family.flatMap { Self.relativeIntensity(of: $0, in: list) },
                                         verdictDetail: indexing.refusalText)
        }
        for (i, ring) in rings.enumerated() {
            out.append(row(id: ring.id, kind: .ring, number: i + 1, radius: ring.radius, calibrating: ring.isCalibrating,
                           refusal: ring.refusal))
        }
        if let centre {
            for (i, spot) in spots.enumerated() {
                let radius = spot.row.flatMap { r in spot.column.map { c in DiffractionCompute.radius(row: r, column: c, centre: centre, ellipse: calibratingEllipse) } }
                out.append(row(id: spot.id, kind: .spot, number: i + 1, radius: radius, calibrating: false, refusal: spot.refusal))
            }
        }
        return out
    }

    /// A family's kinematic intensity of 100 for the list's strongest family; nil when the list does not hold it.
    package static func relativeIntensity(of family: ReflectionFamily, in list: KinematicReflectionList) -> Double? {
        guard let strongest = list.families.map(\.intensity).max(), strongest > 0,
              let listed = list.families.first(where: { $0.family == family }) else { return nil }
        return 100 * listed.intensity / strongest
    }

    // MARK: Export and Results

    package func exportHeader(image: CalibratedImage) -> DiffractionExportHeader {
        let calibration = calibration(for: image)
        let c = centre ?? .imageCentre(width: image.width, height: image.height)
        return DiffractionExportHeader(
            fileName: image.fileName, centreRow: c.row, centreColumn: c.column,
            centreSource: { switch c.source { case .fileCentre: "the image centre"; case .typed: "typed"; case .ring: "a fitted ring" } }(),
            calibration: calibration?.sourceText ?? "none", deltaQ: calibration?.deltaQ, wavelengthAngstroms: calibration?.ring?.wavelengthAngstroms,
            lengthPixels: calibration?.ring?.lengthPixels, lengthMM: calibration?.ring?.lengthMillimetres,
            fitVersusFilePercent: fitVersusFilePercent(for: image), crystal: crystal.name, crystalSHA256: crystal.sha256, kMax: kMax,
            tolerancePercent: tolerancePercent, crystalLattice: DiffractionCrystal.latticeText(crystal.structure.cell, ascii: true),
            crystalPhase: crystal.phaseText)
    }

    package func exportText(image: CalibratedImage) -> String {
        DiffractionExport.text(rows: readout(image: image), header: exportHeader(image: image))
    }

    /// The Results room's rows: one calibration row when a standard fit set the scale, one row per ring and spot.
    package func resultRows(image: CalibratedImage) -> [ResultRow] {
        var out: [ResultRow] = []
        if let calibration = ringCalibration, case .ringFit(let standard, let family) = calibration.source, let ring = calibration.ring {
            out.append(.calibration(id: "calibration", label: "Calibration", standard: standard, family: family, d: ring.d, radius: ring.radius,
                                    deltaQ: ring.deltaQ, wavelength: ring.wavelengthAngstroms, lengthPixels: ring.lengthPixels,
                                    lengthMM: ring.lengthMillimetres, fitVersusFilePercent: fitVersusFilePercent(for: image)))
        }
        for r in readout(image: image) {
            let refusal = r.d == nil ? r.verdict : nil
            out.append(.ring(id: "diffraction:\(r.id.uuidString)", label: "\(r.kind == .ring ? "Ring" : "Spot") \(r.number)", radius: r.radiusPx, q: r.q,
                             d: r.d, family: r.family, dListed: r.dListed, deltaPercent: r.deltaPercent, odds: r.oddsText, verdict: r.verdictWords, refusal: refusal,
                             crystal: "\(crystal.name), \(crystal.lattice)"))
        }
        return out
    }
}
