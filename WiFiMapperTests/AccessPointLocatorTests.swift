import XCTest
@testable import WiFiMapper

final class AccessPointLocatorTests: XCTestCase {
    private let projection = LocalProjection(originLatitude: 37.0, originLongitude: -122.0)

    /// A reading at (x, y) meters from the origin, from a node at `node`, following a
    /// log-distance model plus deterministic "noise".
    private func sample(x: Double, y: Double, node: (x: Double, y: Double), bssid: String,
                        apple: Bool = false, noise: Double = 3) -> LocatorSample {
        let distance = max(hypot(x - node.x, y - node.y), 1)
        let score = SignalScoring.clamp(95 - 35 * log10(distance) + noise * sin(x * 1.7 + y * 0.9))
        let coordinate = projection.unproject(x: x, y: y)
        return LocatorSample(latitude: coordinate.latitude, longitude: coordinate.longitude, bssid: bssid,
                             appleScore: apple ? score : nil, linkScore: apple ? nil : score)
    }

    private func meters(from estimate: AccessPointEstimate, to node: (x: Double, y: Double)) -> Double {
        let p = projection.project(latitude: estimate.latitude, longitude: estimate.longitude)
        return hypot(p.x - node.x, p.y - node.y)
    }

    func testProjectionRoundTrip() {
        let p = projection.project(latitude: 37.0001, longitude: -121.9998)
        let back = projection.unproject(x: p.x, y: p.y)
        XCTAssertEqual(back.latitude, 37.0001, accuracy: 1e-9)
        XCTAssertEqual(back.longitude, -121.9998, accuracy: 1e-9)
        XCTAssertEqual(p.y, 11.1, accuracy: 0.1)
    }

    func testNodeKeyGroupsRadiosAndNormalizes() {
        XCTAssertEqual(AccessPointLocator.nodeKey(for: "A4:2B:B0:1C:3E:7F"), "a4:2b:b0:1c:3e")
        XCTAssertEqual(AccessPointLocator.nodeKey(for: "a4:2b:b0:1c:3e:80"), "a4:2b:b0:1c:3e")
        XCTAssertEqual(AccessPointLocator.nodeKey(for: "a:b:c:d:e:f"), "0a:0b:0c:0d:0e")
        XCTAssertNil(AccessPointLocator.nodeKey(for: "00:00:00:00:00:00"))
        XCTAssertNil(AccessPointLocator.nodeKey(for: "not-a-bssid"))
        XCTAssertNil(AccessPointLocator.nodeKey(for: "a4:2b:b0:1c:3e"))
    }

    func testFitFindsNodeWalkedAroundOnAllSides() throws {
        let node = (x: 4.0, y: -3.0)
        var samples: [LocatorSample] = []
        for x in stride(from: -20.0, through: 20, by: 4) {
            for y in stride(from: -20.0, through: 20, by: 4) {
                samples.append(sample(x: x, y: y, node: node, bssid: "a4:2b:b0:1c:3e:7f"))
            }
        }
        let estimate = try XCTUnwrap(AccessPointLocator.locate(samples).first)
        XCTAssertEqual(estimate.method, .pathLossFit)
        XCTAssertEqual(estimate.source, .latency)
        XCTAssertEqual(estimate.confidence, .high)
        XCTAssertLessThan(meters(from: estimate, to: node), 2.5)
        XCTAssertLessThanOrEqual(estimate.radiusMeters, 6)
    }

    func testFitPlacesNodeOutsideAOneSidedWalk() throws {
        // Walking only along a hallway 8 m south of the node; a centroid would stay on the path.
        let node = (x: 0.0, y: 8.0)
        let samples = stride(from: -20.0, through: 20, by: 2).flatMap { x in
            [sample(x: x, y: 0, node: node, bssid: "a4:2b:b0:1c:3e:7f", noise: 1),
             sample(x: x, y: -3, node: node, bssid: "a4:2b:b0:1c:3e:7f", noise: 1)]
        }
        let estimate = try XCTUnwrap(AccessPointLocator.locate(samples).first)
        XCTAssertEqual(estimate.method, .pathLossFit)
        XCTAssertLessThan(meters(from: estimate, to: node), 4)
    }

    func testFewSamplesFallBackToCentroid() throws {
        let node = (x: 0.0, y: 0.0)
        let samples = [(-3.0, 0.0), (3, 0), (0, 3), (0, -3), (6, 6)].map {
            sample(x: $0.0, y: $0.1, node: node, bssid: "a4:2b:b0:1c:3e:7f")
        }
        let estimate = try XCTUnwrap(AccessPointLocator.locate(samples).first)
        XCTAssertEqual(estimate.method, .weightedCentroid)
        XCTAssertEqual(estimate.confidence, .low)
        XCTAssertLessThan(meters(from: estimate, to: node), 4)
    }

    func testTooFewSamplesGiveNoEstimate() {
        let samples = (0..<3).map { sample(x: Double($0), y: 0, node: (0, 0), bssid: "a4:2b:b0:1c:3e:7f") }
        XCTAssertTrue(AccessPointLocator.locate(samples).isEmpty)
    }

    func testSeparatesNodesAndLabelsInFirstSeenOrder() {
        let nodeA = (x: -10.0, y: 0.0), nodeB = (x: 15.0, y: 5.0)
        var samples: [LocatorSample] = []
        for x in stride(from: -25.0, through: 30, by: 3) {
            for y in stride(from: -12.0, through: 15, by: 3) {
                let onA = hypot(x - nodeA.x, y - nodeA.y) < hypot(x - nodeB.x, y - nodeB.y)
                samples.append(onA ? sample(x: x, y: y, node: nodeA, bssid: "a4:2b:b0:1c:3e:7f")
                                   : sample(x: x, y: y, node: nodeB, bssid: "a4:2b:b0:5d:91:21"))
            }
        }
        let estimates = AccessPointLocator.locate(samples)
        XCTAssertEqual(estimates.map(\.label), ["Node 1", "Node 2"])
        XCTAssertEqual(estimates.map(\.id), ["a4:2b:b0:1c:3e", "a4:2b:b0:5d:91"])
        XCTAssertLessThan(meters(from: estimates[0], to: nodeA), 5)
        XCTAssertLessThan(meters(from: estimates[1], to: nodeB), 5)
    }

    func testCompassDirection() {
        XCTAssertEqual(AccessPointLocator.compassDirection(degrees: 0), "north")
        XCTAssertEqual(AccessPointLocator.compassDirection(degrees: 44), "north-east")
        XCTAssertEqual(AccessPointLocator.compassDirection(degrees: 180), "south")
        XCTAssertEqual(AccessPointLocator.compassDirection(degrees: -90), "west")
        XCTAssertEqual(AccessPointLocator.compassDirection(degrees: 350), "north")
    }

    func testPrefersAppleStrengthWhenMostSamplesHaveIt() throws {
        let node = (x: 0.0, y: 0.0)
        let samples = stride(from: -12.0, through: 12, by: 3).flatMap { x in
            stride(from: -12.0, through: 12, by: 3).map { y in
                sample(x: x, y: y, node: node, bssid: "a4:2b:b0:1c:3e:7f", apple: true)
            }
        }
        XCTAssertEqual(try XCTUnwrap(AccessPointLocator.locate(samples).first).source, .appleStrength)
    }
}
