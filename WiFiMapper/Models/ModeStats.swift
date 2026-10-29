import Foundation

/// Summary numbers used to compare scoring modes on the same recording.
struct ModeStats {
    let mode: ScoringMode
    let totalCount: Int
    let scoredCount: Int
    let mean: Double?
    let minimum: Double?
    let maximum: Double?
    /// Standard deviation. A mode that separates strong and weak spots well has more spread.
    let spread: Double?
    /// Should be strongly negative: higher score ⇔ lower latency.
    let latencyCorrelation: Double?
    /// Should be positive when throughput was measured.
    let throughputCorrelation: Double?

    init(mode: ScoringMode, metrics: [SampleMetrics]) {
        self.mode = mode
        totalCount = metrics.count
        let scored = metrics.compactMap { m in mode.score(m).map { (m, $0) } }
        let scores = scored.map(\.1)
        scoredCount = scores.count
        mean = Stats.mean(scores)
        minimum = scores.min()
        maximum = scores.max()
        spread = Stats.standardDeviation(scores)

        let withRTT = scored.compactMap { pair in pair.0.rttMs.map { ($0, pair.1) } }
        latencyCorrelation = Stats.pearson(withRTT.map(\.0), withRTT.map(\.1))
        let withThroughput = scored.compactMap { pair in pair.0.throughputMbps.map { ($0, pair.1) } }
        throughputCorrelation = Stats.pearson(withThroughput.map(\.0), withThroughput.map(\.1))
    }
}

enum Stats {
    static func mean(_ xs: [Double]) -> Double? {
        xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    static func standardDeviation(_ xs: [Double]) -> Double? {
        guard xs.count > 1, let m = mean(xs) else { return nil }
        let variance = xs.reduce(0) { $0 + ($1 - m) * ($1 - m) } / Double(xs.count - 1)
        return sqrt(variance)
    }

    static func median(_ xs: [Double]) -> Double? {
        guard !xs.isEmpty else { return nil }
        let sorted = xs.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// Pearson correlation coefficient, or nil when there are too few points or no variance.
    static func pearson(_ xs: [Double], _ ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count >= 3, let mx = mean(xs), let my = mean(ys) else { return nil }
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for (x, y) in zip(xs, ys) {
            sxy += (x - mx) * (y - my)
            sxx += (x - mx) * (x - mx)
            syy += (y - my) * (y - my)
        }
        guard sxx > 0, syy > 0 else { return nil }
        return sxy / sqrt(sxx * syy)
    }
}
