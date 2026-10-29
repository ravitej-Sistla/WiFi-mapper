import Foundation

struct HeatPoint: Hashable {
    var latitude: Double
    var longitude: Double
    var value: Double
}

struct HeatEstimate: Equatable {
    var value: Double
    /// Distance in meters to the closest sample that contributed.
    var nearestDistance: Double
}

/// Inverse-distance-weighted interpolation over samples, in a local metric frame.
/// Samples are bucketed by `radius` so a lookup only scans the 3×3 neighboring buckets.
struct IDWInterpolator {
    static let defaultRadius = 12.0

    let radius: Double
    let power: Double
    let count: Int

    private struct BucketKey: Hashable { let x: Int; let y: Int }
    private struct Projected { let x: Double; let y: Double; let value: Double }

    private let originLatitude: Double
    private let originLongitude: Double
    private let metersPerDegreeLongitude: Double
    private static let metersPerDegreeLatitude = 111_132.0
    private var buckets: [BucketKey: [Projected]] = [:]

    init(points: [HeatPoint], radius: Double = IDWInterpolator.defaultRadius, power: Double = 2) {
        self.radius = radius
        self.power = power
        self.count = points.count
        let n = Double(max(points.count, 1))
        originLatitude = points.reduce(0) { $0 + $1.latitude } / n
        originLongitude = points.reduce(0) { $0 + $1.longitude } / n
        metersPerDegreeLongitude = 111_320 * cos(originLatitude * .pi / 180)

        for point in points {
            let (x, y) = project(latitude: point.latitude, longitude: point.longitude)
            buckets[bucketKey(x: x, y: y), default: []].append(Projected(x: x, y: y, value: point.value))
        }
    }

    var isEmpty: Bool { count == 0 }

    /// Interpolated value at a coordinate, or nil when no sample lies within `radius`.
    func estimate(latitude: Double, longitude: Double) -> HeatEstimate? {
        guard !isEmpty else { return nil }
        let (x, y) = project(latitude: latitude, longitude: longitude)
        let key = bucketKey(x: x, y: y)
        var weightSum = 0.0
        var valueSum = 0.0
        var nearest = Double.infinity

        for dx in -1...1 {
            for dy in -1...1 {
                guard let bucket = buckets[BucketKey(x: key.x + dx, y: key.y + dy)] else { continue }
                for p in bucket {
                    let distance = hypot(p.x - x, p.y - y)
                    guard distance <= radius else { continue }
                    nearest = min(nearest, distance)
                    // Clamp tiny distances so a sample under the cursor doesn't get infinite weight.
                    let weight = 1 / pow(max(distance, 0.5), power)
                    weightSum += weight
                    valueSum += weight * p.value
                }
            }
        }
        guard weightSum > 0 else { return nil }
        return HeatEstimate(value: valueSum / weightSum, nearestDistance: nearest)
    }

    private func project(latitude: Double, longitude: Double) -> (Double, Double) {
        ((longitude - originLongitude) * metersPerDegreeLongitude,
         (latitude - originLatitude) * Self.metersPerDegreeLatitude)
    }

    private func bucketKey(x: Double, y: Double) -> BucketKey {
        BucketKey(x: Int(floor(x / radius)), y: Int(floor(y / radius)))
    }
}
