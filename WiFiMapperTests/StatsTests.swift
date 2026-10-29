import XCTest
@testable import WiFiMapper

final class StatsTests: XCTestCase {
    func testMeanMedianAndStandardDeviation() throws {
        XCTAssertNil(Stats.mean([]))
        XCTAssertEqual(Stats.mean([1, 2, 3, 4]), 2.5)
        XCTAssertEqual(Stats.median([5, 1, 3]), 3)
        XCTAssertEqual(Stats.median([4, 1, 3, 2]), 2.5)
        XCTAssertNil(Stats.standardDeviation([1]))
        XCTAssertEqual(try XCTUnwrap(Stats.standardDeviation([2, 4, 4, 4, 5, 5, 7, 9])), 2.138, accuracy: 0.001)
    }

    func testPearson() throws {
        XCTAssertEqual(try XCTUnwrap(Stats.pearson([1, 2, 3, 4], [2, 4, 6, 8])), 1, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(Stats.pearson([1, 2, 3, 4], [8, 6, 4, 2])), -1, accuracy: 1e-9)
        XCTAssertNil(Stats.pearson([1, 2], [1, 2]), "needs at least three points")
        XCTAssertNil(Stats.pearson([1, 2, 3], [5, 5, 5]), "no variance")
    }

    func testModeStatsOnARecording() throws {
        let samples = [3.0, 20, 50, 80].map {
            SampleMetrics(connected: true, appleStrength: nil, rttMs: $0, jitterMs: 0, lossPct: 0, throughputMbps: nil)
        } + [.disconnected]
        let stats = ModeStats(mode: .linkQuality, metrics: samples)
        XCTAssertEqual(stats.totalCount, 5)
        XCTAssertEqual(stats.scoredCount, 5)
        XCTAssertEqual(stats.maximum, 100)
        XCTAssertEqual(stats.minimum, 0)
        XCTAssertLessThan(try XCTUnwrap(stats.latencyCorrelation), -0.9)
        XCTAssertNil(stats.throughputCorrelation)
    }
}
