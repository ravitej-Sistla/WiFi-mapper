import Foundation

/// Raw, mode-independent measurements taken at one spot. Scores are derived from
/// these at display time, so one walk can be viewed under any `ScoringMode`.
struct SampleMetrics: Equatable {
    /// False when the device was not on Wi-Fi at all (a dead zone).
    var connected: Bool
    /// 0...1 from `NEHotspotNetwork.signalStrength`. Nil or 0 when iOS doesn't provide it.
    var appleStrength: Double?
    /// Median TCP-handshake round trip to the router, in milliseconds.
    var rttMs: Double?
    /// Mean absolute difference between consecutive round trips, in milliseconds.
    var jitterMs: Double?
    /// Percentage of router probes that got no answer.
    var lossPct: Double?
    /// Download throughput, when the optional throughput probe is enabled.
    var throughputMbps: Double?

    static let disconnected = SampleMetrics(
        connected: false, appleStrength: nil, rttMs: nil, jitterMs: nil, lossPct: 100, throughputMbps: nil
    )
}

enum ScoringMode: String, CaseIterable, Identifiable {
    case hybrid
    case linkQuality

    /// Used until the user picks a default in Settings.
    static let fallback: ScoringMode = .hybrid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hybrid: "Hybrid"
        case .linkQuality: "Link quality"
        }
    }

    var summary: String {
        switch self {
        case .hybrid:
            "Blends Apple's Wi-Fi signal strength with measured link quality. Falls back to link quality when iOS doesn't report signal strength."
        case .linkQuality:
            "Uses only measured latency, jitter and packet loss to your router (plus throughput if enabled)."
        }
    }

    /// 0...100, or nil when there's nothing to score.
    func score(_ metrics: SampleMetrics) -> Double? {
        switch self {
        case .hybrid: SignalScoring.hybridScore(metrics)
        case .linkQuality: SignalScoring.linkScore(metrics)
        }
    }
}

enum SignalScoring {
    // Tunable thresholds. Round trips to a mesh router are typically 2–10 ms
    // close to a node and climb steeply as the radio link degrades.
    static let bestRTTMs = 3.0
    static let worstRTTMs = 100.0
    static let jitterPenaltyPerMs = 0.5
    static let maxJitterPenalty = 25.0
    static let lossPenaltyPerPct = 1.5
    static let bestThroughputMbps = 300.0
    static let throughputWeight = 0.4

    static func appleScore(_ m: SampleMetrics) -> Double? {
        guard m.connected, let strength = m.appleStrength, strength > 0 else { return nil }
        return clamp(strength * 100)
    }

    static func linkScore(_ m: SampleMetrics) -> Double? {
        guard m.connected else { return 0 }
        guard let rtt = m.rttMs else {
            // Connected, but every probe failed: as bad as it gets. No probe at all: unknown.
            return (m.lossPct ?? 0) >= 100 ? 0 : nil
        }
        let rttScore = 100 * (worstRTTMs - rtt) / (worstRTTMs - bestRTTMs)
        let jitterPenalty = min(maxJitterPenalty, (m.jitterMs ?? 0) * jitterPenaltyPerMs)
        let lossPenalty = (m.lossPct ?? 0) * lossPenaltyPerPct
        var score = clamp(rttScore) - jitterPenalty - lossPenalty

        if let mbps = m.throughputMbps, mbps > 0 {
            let throughputScore = clamp(100 * log10(max(mbps, 1)) / log10(bestThroughputMbps))
            score = (1 - throughputWeight) * score + throughputWeight * throughputScore
        }
        return clamp(score)
    }

    static func hybridScore(_ m: SampleMetrics) -> Double? {
        guard m.connected else { return 0 }
        switch (appleScore(m), linkScore(m)) {
        case let (apple?, link?): return (apple + link) / 2
        case let (apple?, nil): return apple
        case let (nil, link?): return link
        case (nil, nil): return nil
        }
    }

    static func clamp(_ value: Double, _ low: Double = 0, _ high: Double = 100) -> Double {
        min(max(value, low), high)
    }
}

enum SignalQuality {
    case excellent, good, fair, poor

    init(score: Double) {
        switch score {
        case 75...: self = .excellent
        case 50..<75: self = .good
        case 25..<50: self = .fair
        default: self = .poor
        }
    }

    var label: String {
        switch self {
        case .excellent: "Excellent"
        case .good: "Good"
        case .fair: "Fair"
        case .poor: "Poor"
        }
    }
}
