import XCTest
@testable import WiFiMapper

final class InterpolatorTests: XCTestCase {
    private let lat = 37.0
    private let lon = -122.0
    /// About 1 m of latitude, in degrees.
    private let meter = 1 / 111_132.0

    func testEmptyInterpolatorReturnsNil() {
        let idw = IDWInterpolator(points: [])
        XCTAssertTrue(idw.isEmpty)
        XCTAssertNil(idw.estimate(latitude: lat, longitude: lon))
    }

    func testValueAtASingleSample() throws {
        let idw = IDWInterpolator(points: [HeatPoint(latitude: lat, longitude: lon, value: 42)])
        let estimate = try XCTUnwrap(idw.estimate(latitude: lat, longitude: lon))
        XCTAssertEqual(estimate.value, 42, accuracy: 1e-9)
        XCTAssertEqual(estimate.nearestDistance, 0, accuracy: 1e-6)
    }

    func testNilBeyondRadius() {
        let idw = IDWInterpolator(points: [HeatPoint(latitude: lat, longitude: lon, value: 42)], radius: 10)
        XCTAssertNotNil(idw.estimate(latitude: lat + 9 * meter, longitude: lon))
        XCTAssertNil(idw.estimate(latitude: lat + 11 * meter, longitude: lon))
    }

    func testMidpointAveragesAndNearSideDominates() throws {
        let idw = IDWInterpolator(points: [
            HeatPoint(latitude: lat, longitude: lon, value: 0),
            HeatPoint(latitude: lat + 10 * meter, longitude: lon, value: 100),
        ])
        let middle = try XCTUnwrap(idw.estimate(latitude: lat + 5 * meter, longitude: lon))
        XCTAssertEqual(middle.value, 50, accuracy: 0.5)
        XCTAssertEqual(middle.nearestDistance, 5, accuracy: 0.05)

        let nearHigh = try XCTUnwrap(idw.estimate(latitude: lat + 8 * meter, longitude: lon))
        XCTAssertGreaterThan(nearHigh.value, 80)
    }

    func testFindsSamplesInNeighboringBuckets() throws {
        // Points straddle a bucket edge; the lookup must still see both.
        let idw = IDWInterpolator(points: [
            HeatPoint(latitude: lat - 3 * meter, longitude: lon, value: 20),
            HeatPoint(latitude: lat + 3 * meter, longitude: lon, value: 80),
        ], radius: 4)
        let estimate = try XCTUnwrap(idw.estimate(latitude: lat, longitude: lon))
        XCTAssertEqual(estimate.value, 50, accuracy: 0.5)
    }
}
