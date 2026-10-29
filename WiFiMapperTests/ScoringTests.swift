import XCTest
@testable import WiFiMapper

final class ScoringTests: XCTestCase {
    private func metrics(apple: Double? = nil, rtt: Double? = nil, jitter: Double? = 0, loss: Double? = 0,
                         throughput: Double? = nil) -> SampleMetrics {
        SampleMetrics(connected: true, appleStrength: apple, rttMs: rtt, jitterMs: jitter, lossPct: loss, throughputMbps: throughput)
    }

    func testDisconnectedScoresZeroInBothModes() {
        XCTAssertEqual(ScoringMode.hybrid.score(.disconnected), 0)
        XCTAssertEqual(ScoringMode.linkQuality.score(.disconnected), 0)
    }

    func testLinkScoreEndpoints() {
        XCTAssertEqual(SignalScoring.linkScore(metrics(rtt: SignalScoring.bestRTTMs)), 100)
        XCTAssertEqual(SignalScoring.linkScore(metrics(rtt: 1)), 100)
        XCTAssertEqual(SignalScoring.linkScore(metrics(rtt: SignalScoring.worstRTTMs)), 0)
        XCTAssertEqual(SignalScoring.linkScore(metrics(rtt: 500)), 0)
    }

    func testLinkScoreFallsAsLatencyRises() throws {
        let fast = try XCTUnwrap(SignalScoring.linkScore(metrics(rtt: 10)))
        let slow = try XCTUnwrap(SignalScoring.linkScore(metrics(rtt: 50)))
        XCTAssertGreaterThan(fast, slow)
    }

    func testJitterAndLossArePenalized() throws {
        let clean = try XCTUnwrap(SignalScoring.linkScore(metrics(rtt: 10)))
        let jittery = try XCTUnwrap(SignalScoring.linkScore(metrics(rtt: 10, jitter: 10)))
        let lossy = try XCTUnwrap(SignalScoring.linkScore(metrics(rtt: 10, loss: 20)))
        XCTAssertEqual(clean - jittery, 10 * SignalScoring.jitterPenaltyPerMs, accuracy: 1e-9)
        XCTAssertEqual(clean - lossy, 20 * SignalScoring.lossPenaltyPerPct, accuracy: 1e-9)
        let hugeJitter = try XCTUnwrap(SignalScoring.linkScore(metrics(rtt: 3, jitter: 1000)))
        XCTAssertEqual(hugeJitter, 100 - SignalScoring.maxJitterPenalty, accuracy: 1e-9)
    }

    func testAllProbesLostScoresZeroButNoProbeIsUnknown() {
        XCTAssertEqual(SignalScoring.linkScore(metrics(rtt: nil, loss: 100)), 0)
        XCTAssertNil(SignalScoring.linkScore(metrics(rtt: nil, loss: nil)))
    }

    func testThroughputBlend() throws {
        let base = metrics(rtt: SignalScoring.bestRTTMs)
        let withMax = try XCTUnwrap(SignalScoring.linkScore(metrics(rtt: SignalScoring.bestRTTMs, throughput: SignalScoring.bestThroughputMbps)))
        XCTAssertEqual(withMax, 100, accuracy: 1e-9)
        let withSlow = try XCTUnwrap(SignalScoring.linkScore(metrics(rtt: SignalScoring.bestRTTMs, throughput: 1)))
        XCTAssertEqual(withSlow, 100 * (1 - SignalScoring.throughputWeight), accuracy: 1e-9)
        XCTAssertEqual(SignalScoring.linkScore(base), 100)
    }

    func testHybridAveragesAppleAndLink() throws {
        let m = metrics(apple: 0.4, rtt: SignalScoring.bestRTTMs)
        XCTAssertEqual(try XCTUnwrap(ScoringMode.hybrid.score(m)), 70, accuracy: 1e-9)
        XCTAssertEqual(ScoringMode.linkQuality.score(m), 100)
    }

    func testHybridFallsBackToLinkWhenAppleStrengthMissingOrZero() {
        let link = SignalScoring.linkScore(metrics(rtt: 20))
        XCTAssertEqual(ScoringMode.hybrid.score(metrics(apple: nil, rtt: 20)), link)
        XCTAssertEqual(ScoringMode.hybrid.score(metrics(apple: 0, rtt: 20)), link)
    }

    func testHybridUsesAppleAloneWhenNoLinkMeasurement() {
        XCTAssertEqual(ScoringMode.hybrid.score(metrics(apple: 0.8, rtt: nil, loss: nil)), 80)
    }

    func testQualityBands() {
        XCTAssertEqual(SignalQuality(score: 90), .excellent)
        XCTAssertEqual(SignalQuality(score: 75), .excellent)
        XCTAssertEqual(SignalQuality(score: 60), .good)
        XCTAssertEqual(SignalQuality(score: 30), .fair)
        XCTAssertEqual(SignalQuality(score: 10), .poor)
    }
}
