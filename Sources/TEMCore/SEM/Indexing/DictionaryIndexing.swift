//
//  DictionaryIndexing.swift
//  Role: EBSD dictionary indexing (Chen et al. 2015, Jackson et al. 2019): every experimental pattern compared with every
//        pattern of a dictionary of known orientations by a similarity metric, the `keepN` best matches kept per pattern. A port
//        of kikuchipy 0.13.1's `EBSD.dictionary_indexing` and `indexing/_dictionary_indexing.py` (`_dictionary_indexing`,
//        `_match_chunk`) with its two metrics, `NormalizedCrossCorrelationMetric` ("ncc": each pattern centred to zero mean
//        and scaled to unit norm, the Pearson coefficient) and `NormalizedDotProductMetric` ("ndp": unit norm only), the
//        signal and navigation masks and the dictionary taken in chunks; GPL-3.0-or-later, notice in NOTICE.
//        The dictionary either comes in full or is projected chunk by chunk from a master pattern (`MasterPatternProjection`,
//        figure F15) for a sample of orientations (`OrientationSampling.fundamental`), so a large dictionary never sits in
//        memory whole. The float64 CPU path is the reference (decision D16); `DictionaryIndexingMetal` is the float32 GPU path
//        for the matrix product of patterns x dictionary, checked against this one.
//        Parity: macTEMTests/SEMDictionaryIndexingParityTests.swift against tools/parity/sem/references/m4/dictionary-indexing-*
//        (figure F9): scores within rtol 1e-4 of kikuchipy's float32 run and 1e-5 of its float64 run, simulation indices exact
//        where the scores do not tie.
//

import Foundation

package nonisolated enum DictionaryIndexing {
    /// kikuchipy's `metric`: "ncc" (the default) or "ndp". Greater is better for both.
    package enum Metric: String, Sendable, CaseIterable {
        case ncc, ndp

        /// NCC centres each pattern before it scales it to unit norm; NDP only scales (its code, whatever its docstring says).
        var centres: Bool { self == .ncc }
    }

    /// Where the matrix product runs: the float64 CPU reference, the float32 GPU path, or the GPU when the work pays and a device
    /// is there.
    package enum Backend: Sendable, Equatable { case automatic, cpu, metal }

    package struct Options: Sendable, Equatable {
        package var metric: Metric
        /// `keep_n`: best matches kept per pattern, at most the dictionary's size.
        package var keepN: Int
        /// `signal_mask`, detector row-major: `true` leaves the pixel out of the comparison.
        package var signalMask: [Bool]?
        /// `navigation_mask`, scan row-major: `true` leaves the pattern out (it is not indexed).
        package var navigationMask: [Bool]?
        /// `n_per_iteration`: dictionary patterns compared per chunk; nil sizes the chunk from `memoryBudget`.
        package var patternsPerIteration: Int?
        /// Bytes the chunk's dictionary patterns and score matrix may take when `patternsPerIteration` is nil.
        package var memoryBudget: Int
        package var backend: Backend

        package init(metric: Metric = .ncc, keepN: Int = 20, signalMask: [Bool]? = nil, navigationMask: [Bool]? = nil,
                     patternsPerIteration: Int? = nil, memoryBudget: Int = 256 << 20, backend: Backend = .automatic) {
            self.metric = metric; self.keepN = keepN; self.signalMask = signalMask; self.navigationMask = navigationMask
            self.patternsPerIteration = patternsPerIteration; self.memoryBudget = memoryBudget; self.backend = backend
        }
    }

    package enum Error: Swift.Error, LocalizedError, Equatable {
        case emptyDictionary
        case keepN(Int)
        case patternCount(values: Int, patterns: Int, pixels: Int)
        case navigationShape([Int], patterns: Int)
        case rotationCount(rotations: Int, patterns: Int)
        case signalMaskShape(mask: Int, pixels: Int)
        case navigationMaskShape(mask: Int, patterns: Int)
        case signalMaskAll
        case navigationMaskAll
        case patternsPerIteration(Int)

        package var errorDescription: String? {
            switch self {
            case .emptyDictionary: return "The dictionary holds no patterns."
            case .keepN(let n): return "keep_n must be at least 1, not \(n)."
            case .patternCount(let v, let p, let px): return "\(v) values are not \(p) patterns of \(px) pixels."
            case .navigationShape(let s, let p): return "The navigation shape \(s) does not hold \(p) patterns."
            case .rotationCount(let r, let p): return "The dictionary has \(p) patterns but \(r) rotations."
            case .signalMaskShape(let m, let px): return "The signal mask has \(m) pixels, the patterns \(px)."
            case .navigationMaskShape(let m, let p): return "The navigation mask has \(m) points, the scan \(p)."
            case .signalMaskAll: return "The signal mask leaves no pixel to compare."
            case .navigationMaskAll: return "The navigation mask must allow for indexing of at least one pattern."
            case .patternsPerIteration(let n): return "n_per_iteration must be at least 1, not \(n)."
            }
        }
    }

    /// The crystal map kikuchipy returns: per scan point (row-major) `keepN` matches, best first.
    package struct Result: Sendable, Equatable {
        /// Scan rows, columns (one entry for a line scan).
        package var navigationShape: [Int]
        package var keepN: Int
        /// orix's `is_in_data`: false where the navigation mask left the point out.
        package var isInData: [Bool]
        /// `prop["scores"]`, point × keepN; NaN for a point not in the data (kikuchipy leaves `np.empty`'s garbage there).
        package var scores: [Double]
        /// `prop["simulation_indices"]` into the dictionary, point × keepN; -1 for a point not in the data.
        package var simulationIndices: [Int]
        /// The dictionary's rotation (a, b, c, d) at each simulation index, point × keepN; the identity for a point not in the data.
        package var rotations: [SIMD4<Double>]

        package init(navigationShape: [Int], keepN: Int, isInData: [Bool], scores: [Double], simulationIndices: [Int],
                     rotations: [SIMD4<Double>]) {
            self.navigationShape = navigationShape; self.keepN = keepN; self.isInData = isInData
            self.scores = scores; self.simulationIndices = simulationIndices; self.rotations = rotations
        }

        package var pointCount: Int { isInData.count }

        /// The best match of each point.
        package var bestScores: [Double] { stride(from: 0, to: scores.count, by: Swift.max(keepN, 1)).map { scores[$0] } }
        package var bestSimulationIndices: [Int] { stride(from: 0, to: simulationIndices.count, by: Swift.max(keepN, 1)).map { simulationIndices[$0] } }
        package var bestRotations: [SIMD4<Double>] { stride(from: 0, to: rotations.count, by: Swift.max(keepN, 1)).map { rotations[$0] } }

        /// The result as the app's `CrystalMap`, as kikuchipy builds it: the best match's rotation per point (the identity where the
        /// navigation mask left the point out, which is then not in the data), the dictionary's phase as id 0, orix's
        /// `create_coordinate_arrays` from the step sizes (dy, dx), and the best score and simulation index as the properties
        /// `scores` and `simulation_indices` (kikuchipy keeps all keep_n columns; the app's map holds one value per point, the
        /// full ranking stays in this result).
        package func crystalMap(phase: CrystalPhase, stepSizes: [Double], scanUnit: String = "px") throws -> CrystalMap {
            let rows = navigationShape.count == 2 ? navigationShape[0] : 1
            let columns = navigationShape.last ?? 0
            let dy = stepSizes.count == 2 ? stepSizes[0] : 1, dx = stepSizes.last ?? 1
            let (x, y) = CrystalMap.coordinates(shape: (rows, columns), steps: (dy, dx))
            return try CrystalMap(rotations: bestRotations, x: x, y: navigationShape.count == 2 ? y : nil,
                                  phaseList: PhaseList([(id: 0, phase: phase)]),
                                  properties: ["scores": bestScores, "simulation_indices": bestSimulationIndices.map(Double.init)],
                                  scanUnit: scanUnit, isInData: isInData)
        }
    }

    // MARK: - Preparation

    /// The pixels the comparison uses: those the signal mask leaves in, all without a mask.
    static func keptPixels(_ mask: [Bool]?, pixels: Int) throws -> [Int] {
        guard let mask else { return Array(0 ..< pixels) }
        guard mask.count == pixels else { throw Error.signalMaskShape(mask: mask.count, pixels: pixels) }
        let kept = (0 ..< pixels).filter { !mask[$0] }
        guard !kept.isEmpty else { throw Error.signalMaskAll }
        return kept
    }

    /// `prepare_experimental` / `prepare_dictionary` in float64: the kept pixels of `count` patterns (row-major in `values`, a
    /// pattern of `pixels` values every `pixels`), centred for NCC, divided by their Euclidean norm. A flat pattern divides zero by
    /// zero, so its values are NaN, as kikuchipy's are.
    package static func prepare(_ values: UnsafeBufferPointer<Double>, count: Int, pixels: Int, kept: [Int], metric: Metric) -> [Double] {
        var out = [Double](repeating: 0, count: count * kept.count)
        guard let source = values.baseAddress else { return out }   // no pattern, nothing to copy
        out.withUnsafeMutableBufferPointer { o in
            guard let target = o.baseAddress else { return }
            prepare(source, count: count, pixels: pixels, kept: kept, metric: metric, into: target)
        }
        return out
    }

    /// `prepare` of the patterns `patterns` of a block held at its stored type, each widened to float64 as it is prepared (#620): the
    /// numbers of `prepare` on the block's doubles, without a float64 copy of the block.
    package static func prepare(_ stored: StoredPatterns, patterns: [Int], kept: [Int], metric: Metric) -> [Double] {
        var out = [Double](repeating: 0, count: patterns.count * kept.count)
        out.withUnsafeMutableBufferPointer { o in
            guard let target = o.baseAddress else { return }   // no pattern, nothing to prepare
            prepare(stored, patterns: patterns, kept: kept, metric: metric, into: target)
        }
        return out
    }

    /// Centres (NCC) and scales the `n` values at `dst` in place: the preparation itself, in float64.
    @inline(__always)
    private static func normalise(_ dst: UnsafeMutablePointer<Double>, _ n: Int, metric: Metric) {
        if metric.centres {
            var sum = 0.0
            for k in 0 ..< n { sum += dst[k] }
            let mean = sum / Double(n)
            for k in 0 ..< n { dst[k] -= mean }
        }
        var squares = 0.0
        for k in 0 ..< n { squares += dst[k] * dst[k] }
        let norm = squares.squareRoot()
        for k in 0 ..< n { dst[k] /= norm }
    }

    /// Patterns prepared per worker job: enough to pay for the job, few enough to spread a chunk over the cores.
    private static let patternsPerJob = 64

    /// The pointers the preparing workers share: each pattern reads its own values and writes its own row.
    private struct PreparePointers<Source, Target>: @unchecked Sendable {
        let source: UnsafePointer<Source>
        let target: UnsafeMutablePointer<Target>
    }

    /// `prepare` of `count` raw patterns (float64, or the float32 a GPU projection gives, widened exactly) written as `U` to `out`,
    /// row-major: float64 for the CPU, float32 straight into the GPU's buffer. Each pattern is widened and prepared in float64 as
    /// before; the patterns are spread over the cores (#624).
    static func prepare<T: BinaryFloatingPoint, U: BinaryFloatingPoint>(_ source: UnsafePointer<T>, count: Int, pixels: Int, kept: [Int],
                                                                        metric: Metric, into out: UnsafeMutablePointer<U>) {
        let n = kept.count
        guard count > 0, n > 0 else { return }
        let all = n == pixels
        let shared = PreparePointers(source: source, target: out)
        let jobs = (count + patternsPerJob - 1) / patternsPerJob
        DispatchQueue.concurrentPerform(iterations: jobs) { job in
            var scratch = [Double](repeating: 0, count: n)
            scratch.withUnsafeMutableBufferPointer { s in
                guard let dst = s.baseAddress else { return }
                for p in (job * patternsPerJob) ..< min(count, (job + 1) * patternsPerJob) {
                    let src = shared.source + p * pixels
                    if all { for k in 0 ..< n { dst[k] = Double(src[k]) } } else { for k in 0 ..< n { dst[k] = Double(src[kept[k]]) } }
                    normalise(dst, n, metric: metric)
                    let row = shared.target + p * n
                    for k in 0 ..< n { row[k] = U(dst[k]) }
                }
            }
        }
    }

    /// `prepare` of the block's patterns `patterns` (stored type, widened to float64 per pattern) written as `U` to `out`, pattern
    /// after pattern, spread over the cores.
    static func prepare<U: BinaryFloatingPoint>(_ stored: StoredPatterns, patterns: [Int], kept: [Int], metric: Metric,
                                                into out: UnsafeMutablePointer<U>) {
        let n = kept.count
        guard !patterns.isEmpty, n > 0 else { return }
        let mask: [Int]? = n == stored.pixels ? nil : kept
        let shared = PreparePointers<U, U>(source: UnsafePointer(out), target: out)
        let count = patterns.count
        let jobs = (count + patternsPerJob - 1) / patternsPerJob
        DispatchQueue.concurrentPerform(iterations: jobs) { job in
            var scratch = [Double](repeating: 0, count: n)
            scratch.withUnsafeMutableBufferPointer { s in
                guard let dst = s.baseAddress else { return }
                for p in (job * patternsPerJob) ..< min(count, (job + 1) * patternsPerJob) {
                    stored.gather(pattern: patterns[p], kept: mask, into: dst)
                    normalise(dst, n, metric: metric)
                    let row = shared.target + p * n
                    for k in 0 ..< n { row[k] = U(dst[k]) }
                }
            }
        }
    }

    // MARK: - Matching

    /// `metric.match` on the CPU in float64: the scores of every experimental pattern (rows) against every dictionary pattern
    /// (columns), `experimental · dictionaryᵀ`, both already prepared with `length` values per pattern. Each score is one dot product
    /// in a fixed order, so the float64 reference gives the same bits for any chunking (`testChunksGiveTheSameResult`); a BLAS
    /// product (#624) would block the sums by the matrices' shapes, and a chunk's shape would move a score's last bit and, on a tie,
    /// the index kept. The GPU path is where the product's size pays.
    static func matchCPU(experimental e: [Double], count nExp: Int, dictionary d: [Double], count nDict: Int, length: Int) -> [Double] {
        var scores = [Double](repeating: 0, count: nExp * nDict)
        // Blocks of experimental patterns that stay in cache while a block of dictionary patterns streams past.
        let expBlock = 32, dictBlock = 64
        let expBlocks = (nExp + expBlock - 1) / expBlock, dictBlocks = (nDict + dictBlock - 1) / dictBlock
        e.withUnsafeBufferPointer { ep in
            d.withUnsafeBufferPointer { dp in
                scores.withUnsafeMutableBufferPointer { sp in
                    // An empty pattern or dictionary has no score to compute.
                    guard let e = ep.baseAddress, let dBase = dp.baseAddress, let s = sp.baseAddress else { return }
                    let shared = MatchBuffers(e: e, d: dBase, s: s)
                    DispatchQueue.concurrentPerform(iterations: expBlocks * dictBlocks) { job in
                        let eb = job / dictBlocks, db = job % dictBlocks
                        let i0 = eb * expBlock, i1 = min(nExp, i0 + expBlock)
                        let m0 = db * dictBlock, m1 = min(nDict, m0 + dictBlock)
                        for m in m0 ..< m1 {
                            let dm = shared.d + m * length
                            for i in i0 ..< i1 { shared.s[i * nDict + m] = dot(shared.e + i * length, dm, length) }
                        }
                    }
                }
            }
        }
        return scores
    }

    /// The dot product of two float64 vectors, four lanes at a time.
    @inline(__always)
    static func dot(_ a: UnsafePointer<Double>, _ b: UnsafePointer<Double>, _ n: Int) -> Double {
        var acc0 = SIMD4<Double>(repeating: 0), acc1 = SIMD4<Double>(repeating: 0)
        let ra = UnsafeRawPointer(a), rb = UnsafeRawPointer(b)
        var k = 0
        let stride = MemoryLayout<Double>.stride
        while k + 8 <= n {
            acc0 += ra.loadUnaligned(fromByteOffset: k * stride, as: SIMD4<Double>.self) * rb.loadUnaligned(fromByteOffset: k * stride, as: SIMD4<Double>.self)
            acc1 += ra.loadUnaligned(fromByteOffset: (k + 4) * stride, as: SIMD4<Double>.self) * rb.loadUnaligned(fromByteOffset: (k + 4) * stride, as: SIMD4<Double>.self)
            k += 8
        }
        var sum = (acc0 + acc1).sum()
        while k < n { sum += a[k] * b[k]; k += 1 }
        return sum
    }

    private struct MatchBuffers: @unchecked Sendable {
        let e: UnsafePointer<Double>
        let d: UnsafePointer<Double>
        let s: UnsafeMutablePointer<Double>
    }

    /// Whether score `a` (at dictionary index `ia`) ranks before `b` (at `ib`): greater first, a NaN last, a tie by the lower index.
    /// kikuchipy breaks ties by `argsort`'s order, which is not stable; the lower index makes the result the same for any chunking.
    @inline(__always)
    static func ranksBefore(_ a: Double, _ ia: Int, _ b: Double, _ ib: Int) -> Bool {
        if a.isNaN { return b.isNaN && ia < ib }
        if b.isNaN { return true }
        return a > b || (a == b && ia < ib)
    }

    /// The pointers the merging workers share: each experimental pattern reads its own score row and writes its own `keepN` slots.
    private struct MergePointers<S>: @unchecked Sendable {
        let chunk: UnsafePointer<S>
        let scores: UnsafeMutablePointer<Double>
        let indices: UnsafeMutablePointer<Int>
        let filled: UnsafeMutablePointer<Int>
    }

    /// The best `keepN` matches of each experimental pattern so far, merged chunk by chunk (`_dictionary_indexing`'s hstack, sort
    /// and `take_along_axis`). Held flat (pattern × keepN, best first, `filled` per pattern) and merged over the cores, pattern by
    /// pattern (#624); `ranksBefore` is a total order, so the kept matches do not depend on the chunks or the order they merge in.
    struct Best {
        let keepN: Int
        let patterns: Int
        var scores: [Double]
        var indices: [Int]
        var filled: [Int]

        init(patterns: Int, keepN: Int) {
            self.keepN = keepN
            self.patterns = patterns
            scores = Array(repeating: .nan, count: patterns * keepN)
            indices = Array(repeating: -1, count: patterns * keepN)
            filled = Array(repeating: 0, count: patterns)
        }

        /// Merges a chunk's score matrix (patterns × `count`, row-major, float64 from the CPU or float32 from the GPU, widened
        /// exactly), whose column 0 is dictionary index `offset`.
        mutating func merge<S: BinaryFloatingPoint>(_ chunk: UnsafePointer<S>, count: Int, offset: Int) {
            guard patterns > 0, count > 0, keepN > 0 else { return }
            let k = keepN, n = patterns
            let rowsPerJob = 32
            let jobs = (n + rowsPerJob - 1) / rowsPerJob
            scores.withUnsafeMutableBufferPointer { sp in
                indices.withUnsafeMutableBufferPointer { ip in
                    filled.withUnsafeMutableBufferPointer { fp in
                        guard let s0 = sp.baseAddress, let i0 = ip.baseAddress, let f0 = fp.baseAddress else { return }
                        let shared = MergePointers(chunk: chunk, scores: s0, indices: i0, filled: f0)
                        DispatchQueue.concurrentPerform(iterations: jobs) { job in
                            for i in (job * rowsPerJob) ..< min(n, (job + 1) * rowsPerJob) {
                                let s = shared.scores + i * k, idx = shared.indices + i * k
                                let row = shared.chunk + i * count
                                var f = shared.filled[i]
                                for m in 0 ..< count {
                                    let x = Double(row[m]), j = offset + m
                                    if f == k, !DictionaryIndexing.ranksBefore(x, j, s[k - 1], idx[k - 1]) { continue }
                                    // Insert in rank order, dropping the last when full.
                                    var pos = f
                                    while pos > 0, DictionaryIndexing.ranksBefore(x, j, s[pos - 1], idx[pos - 1]) { pos -= 1 }
                                    var t = Swift.min(f, k - 1)
                                    while t > pos {
                                        s[t] = s[t - 1]; idx[t] = idx[t - 1]
                                        t -= 1
                                    }
                                    s[pos] = x; idx[pos] = j
                                    if f < k { f += 1 }
                                }
                                shared.filled[i] = f
                            }
                        }
                    }
                }
            }
        }
    }

    /// The patterns per chunk: `patternsPerIteration`, or as many as the memory budget holds for the chunk's prepared dictionary
    /// and its score matrix (at least one).
    package static func chunkSize(_ options: Options, experimental: Int, length: Int, dictionary: Int) throws -> Int {
        if let n = options.patternsPerIteration {
            guard n >= 1 else { throw Error.patternsPerIteration(n) }
            return min(n, dictionary)
        }
        let perPattern = (length + experimental) * MemoryLayout<Double>.stride
        return max(1, min(dictionary, options.memoryBudget / max(perPattern, 1)))
    }

    /// Whether the GPU computes the products: asked for, or automatic and the work (patterns × dictionary × pixels) pays.
    static func usesMetal(_ backend: Backend, work: Int) -> Bool {
        switch backend {
        case .cpu: return false
        case .metal: return true
        case .automatic: return work >= DictionaryIndexingMetal.workThreshold && DictionaryIndexingMetal.isAvailable
        }
    }

    // MARK: - Indexing

    /// Doubles as a float64 block, refused as before when they are not whole patterns.
    private static func stored(_ values: [Double], pixels: Int) throws -> StoredPatterns {
        guard pixels > 0, values.count % pixels == 0 else {
            throw Error.patternCount(values: values.count, patterns: pixels > 0 ? values.count / pixels : 0, pixels: pixels)
        }
        return try StoredPatterns(doubles: values, pixels: pixels)
    }

    /// The checked experimental side: navigation shape, masks, the points in the data and the pixels kept. The patterns are
    /// prepared by the backend that matches them: in float64 for the CPU, straight into the GPU's float32 buffer for the GPU.
    private struct Experimental {
        let count: Int
        let inData: [Bool]
        let indexed: [Int]
        let kept: [Int]
        let patterns: StoredPatterns
    }

    private static func experimentalSide(_ experimental: StoredPatterns, navigationShape: [Int], pixels: Int, options: Options) throws -> Experimental {
        guard options.keepN >= 1 else { throw Error.keepN(options.keepN) }
        guard pixels > 0, experimental.pixels == pixels else {
            let values = experimental.count * experimental.pixels
            throw Error.patternCount(values: values, patterns: pixels > 0 ? values / pixels : 0, pixels: pixels)
        }
        let count = experimental.count
        guard !navigationShape.isEmpty, navigationShape.reduce(1, *) == count else { throw Error.navigationShape(navigationShape, patterns: count) }
        var inData = [Bool](repeating: true, count: count)
        if let mask = options.navigationMask {
            guard mask.count == count else { throw Error.navigationMaskShape(mask: mask.count, patterns: count) }
            inData = mask.map { !$0 }
            guard inData.contains(true) else { throw Error.navigationMaskAll }
        }
        let kept = try keptPixels(options.signalMask, pixels: pixels)
        let indexed = (0 ..< count).filter { inData[$0] }
        return Experimental(count: count, inData: inData, indexed: indexed, kept: kept, patterns: experimental)
    }

    /// The chunks done and the chunks in all, after each chunk merges (and once with 0 before the first); called on the indexing thread.
    package typealias Progress = @Sendable (_ done: Int, _ total: Int) -> Void

    /// One chunk of raw dictionary patterns (float32-valued, row-major, `pixels` values each) as its source holds it: doubles from a
    /// dictionary in memory or the CPU projection, floats from the GPU projection.
    enum RawChunk {
        case doubles(UnsafeBufferPointer<Double>)
        case floats(UnsafeBufferPointer<Float>)
    }

    /// Runs the chunks: `chunk(start, end, use)` hands the dictionary patterns `start ..< end` to `use`, which prepares, matches and
    /// merges them on the chosen backend. On the GPU two chunks are in flight: one is prepared and merged on the CPU while the
    /// other's product runs, in buffers made once per run (#624). Inside a task, a cancelled task stops before the next chunk
    /// (`CancellationError`); `progress` hears of each chunk merged.
    private static func run(_ exp: Experimental, pixels: Int, dictionarySize: Int, rotations: [SIMD4<Double>], navigationShape: [Int],
                            options: Options, progress: Progress? = nil,
                            chunk: (Int, Int, (RawChunk) throws -> Void) throws -> Void) throws -> Result {
        guard dictionarySize > 0 else { throw Error.emptyDictionary }
        let keepN = min(options.keepN, dictionarySize)
        let length = exp.kept.count, nExp = exp.indexed.count
        let per = try chunkSize(options, experimental: nExp, length: length, dictionary: dictionarySize)
        let metal = usesMetal(options.backend, work: nExp * dictionarySize * length)
        var best = Best(patterns: nExp, keepN: keepN)
        let chunks = (dictionarySize + per - 1) / per
        var done = 0
        let metric = options.metric, kept = exp.kept
        progress?(0, chunks)
        if metal {
            let gpu = try DictionaryIndexingMetal.Matcher(count: nExp, length: length, capacity: per) { target in
                prepare(exp.patterns, patterns: exp.indexed, kept: kept, metric: metric, into: target)
            }
            let merged: (UnsafePointer<Float>, Int, Int) -> Void = { scores, size, offset in
                best.merge(scores, count: size, offset: offset)
                done += 1
                progress?(done, chunks)
            }
            var start = 0
            while start < dictionarySize {
                try Task.checkCancellation()
                let end = min(dictionarySize, start + per)
                try chunk(start, end) { raw in
                    try gpu.submit(size: end - start, offset: start, completed: merged) { target in
                        switch raw {
                        case .doubles(let v):
                            if let base = v.baseAddress {
                                prepare(base, count: end - start, pixels: pixels, kept: kept, metric: metric, into: target)
                            }
                        case .floats(let v):
                            if let base = v.baseAddress {
                                prepare(base, count: end - start, pixels: pixels, kept: kept, metric: metric, into: target)
                            }
                        }
                    }
                }
                start = end
            }
            try gpu.finish(completed: merged)
        } else {
            let prepared = prepare(exp.patterns, patterns: exp.indexed, kept: kept, metric: metric)
            var start = 0
            while start < dictionarySize {
                try Task.checkCancellation()
                let end = min(dictionarySize, start + per), size = end - start
                try chunk(start, end) { raw in
                    var dictionary = [Double](repeating: 0, count: size * length)
                    dictionary.withUnsafeMutableBufferPointer { d in
                        guard let target = d.baseAddress else { return }
                        switch raw {
                        case .doubles(let v):
                            if let base = v.baseAddress {
                                prepare(base, count: size, pixels: pixels, kept: kept, metric: metric, into: target)
                            }
                        case .floats(let v):
                            if let base = v.baseAddress {
                                prepare(base, count: size, pixels: pixels, kept: kept, metric: metric, into: target)
                            }
                        }
                    }
                    let scores = matchCPU(experimental: prepared, count: nExp, dictionary: dictionary, count: size, length: length)
                    scores.withUnsafeBufferPointer { s in
                        if let base = s.baseAddress { best.merge(base, count: size, offset: start) }
                    }
                }
                done += 1
                progress?(done, chunks)
                start = end
            }
        }
        var result = Result(navigationShape: navigationShape, keepN: keepN, isInData: exp.inData,
                            scores: [Double](repeating: .nan, count: exp.count * keepN),
                            simulationIndices: [Int](repeating: -1, count: exp.count * keepN),
                            rotations: [SIMD4<Double>](repeating: SIMD4(1, 0, 0, 0), count: exp.count * keepN))
        for (row, point) in exp.indexed.enumerated() {
            for r in 0 ..< keepN {
                let j = best.indices[row * keepN + r]
                result.scores[point * keepN + r] = best.scores[row * keepN + r]
                result.simulationIndices[point * keepN + r] = j
                result.rotations[point * keepN + r] = rotations[j]
            }
        }
        return result
    }

    /// `EBSD.dictionary_indexing` against a dictionary in memory: `experimental` holds the scan's patterns (scan row-major, then
    /// detector row-major, any data type as doubles), `dictionary` the simulated patterns of the same detector, one per rotation
    /// (a, b, c, d) in `rotations`. kikuchipy casts both to the metric's float type first; pass the dictionary as float32 values
    /// (`get_patterns`' default) to compare with it.
    package static func index(experimental: [Double], navigationShape: [Int], dictionary: [Double], rotations: [SIMD4<Double>],
                              pixels: Int, options: Options = Options()) throws -> Result {
        let exp = try experimentalSide(try stored(experimental, pixels: pixels), navigationShape: navigationShape, pixels: pixels, options: options)
        guard !dictionary.isEmpty else { throw Error.emptyDictionary }
        guard dictionary.count % pixels == 0 else {
            throw Error.patternCount(values: dictionary.count, patterns: dictionary.count / pixels, pixels: pixels)
        }
        let size = dictionary.count / pixels
        guard rotations.count == size else { throw Error.rotationCount(rotations: rotations.count, patterns: size) }
        return try run(exp, pixels: pixels, dictionarySize: size, rotations: rotations, navigationShape: navigationShape, options: options) { s, e, use in
            try dictionary[(s * pixels) ..< (e * pixels)].withUnsafeBufferPointer { try use(.doubles($0)) }
        }
    }

    /// Dictionary indexing against the master pattern projected onto `detector` for each rotation, chunk by chunk
    /// (`EBSDMasterPattern.get_patterns(rotations, detector, energy, dtype_out=float32)` then `dictionary_indexing`): the dictionary
    /// is never held whole. The projection runs on the GPU when the matching does (`MasterPatternProjectionMetal.Projector`, the
    /// master pattern uploaded once per run).
    package static func index(experimental: [Double], navigationShape: [Int], master: EBSDMasterPattern, rotations: [SIMD4<Double>],
                              detector: EBSDDetectorGeometry, energy: Double? = nil, options: Options = Options(),
                              progress: Progress? = nil) throws -> Result {
        try index(experimental: try stored(experimental, pixels: detector.rows * detector.columns), navigationShape: navigationShape,
                  master: master, rotations: rotations, detector: detector, energy: energy, options: options, progress: progress)
    }

    /// `index(experimental:navigationShape:master:…)` on a block held at its stored type (`DictionaryIndexingPlan.readBlock`, #620): each
    /// pattern is widened to float64 as it is prepared, so the scores are those of the block's doubles.
    package static func index(experimental: StoredPatterns, navigationShape: [Int], master: EBSDMasterPattern, rotations: [SIMD4<Double>],
                              detector: EBSDDetectorGeometry, energy: Double? = nil, options: Options = Options(),
                              progress: Progress? = nil) throws -> Result {
        let pixels = detector.rows * detector.columns
        let exp = try experimentalSide(experimental, navigationShape: navigationShape, pixels: pixels, options: options)
        guard !rotations.isEmpty else { throw Error.emptyDictionary }
        let length = exp.kept.count
        let metal = usesMetal(options.backend, work: exp.indexed.count * rotations.count * length)
        // The GPU projects into buffers made once for the run's chunk size, the master pattern uploaded once (#624).
        let projector = try metal
            ? MasterPatternProjectionMetal.Projector(master: master, detector: detector, energy: energy,
                                                         capacity: chunkSize(options, experimental: exp.indexed.count, length: length,
                                                                             dictionary: rotations.count))
            : nil
        return try run(exp, pixels: pixels, dictionarySize: rotations.count, rotations: rotations, navigationShape: navigationShape,
                       options: options, progress: progress) { s, e, use in
            if let projector {
                try projector.withPatterns(rotations[s ..< e]) { try use(.floats($0)) }
                return
            }
            let patterns = try MasterPatternProjection.project(master: master, rotations: Array(rotations[s ..< e]), detector: detector,
                                                               energy: energy, output: .float32)
            try patterns.values.withUnsafeBufferPointer { try use(.doubles($0)) }
        }
    }

    /// `index(experimental:navigationShape:master:rotations:detector:energy:options:progress:)` off the caller's actor (seconds to
    /// minutes); cancelling the calling task stops it before the next chunk.
    @concurrent package static func indexAsync(experimental: StoredPatterns, navigationShape: [Int], master: EBSDMasterPattern,
                                               rotations: [SIMD4<Double>], detector: EBSDDetectorGeometry, energy: Double? = nil,
                                               options: Options = Options(), progress: Progress? = nil) async throws -> Result {
        try index(experimental: experimental, navigationShape: navigationShape, master: master, rotations: rotations,
                  detector: detector, energy: energy, options: options, progress: progress)
    }
}
