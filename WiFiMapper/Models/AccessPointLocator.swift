import Foundation

/// One reading for locating the access point it was taken on.
struct LocatorSample: Equatable {
    var latitude: Double
    var longitude: Double
    var bssid: String
    /// 0...100 from `NEHotspotNetwork.signalStrength`, when iOS reports it.
    var appleScore: Double?
    /// 0...100 from latency, jitter and loss to the router.
    var linkScore: Double?
}

struct AccessPointEstimate: Identifiable, Equatable {
    enum Method: Equatable {
        /// Best fit of a log-distance signal model; can place the node outside the walked path.
        case pathLossFit
        /// Weighted average position of the strongest samples; always inside the walked area.
        case weightedCentroid
    }

    enum Confidence: Int, Comparable {
        case low, medium, high

        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }

        var label: String {
            switch self {
            case .low: "Low"
            case .medium: "Medium"
            case .high: "High"
            }
        }
    }

    enum SignalSource: Equatable {
        case appleStrength, latency

        var label: String {
            switch self {
            case .appleStrength: "signal strength"
            case .latency: "latency"
            }
        }
    }

    /// Node key: the BSSID without its last octet, shared by a node's radios.
    let id: String
    var label: String
    var bssids: [String]
    var latitude: Double
    var longitude: Double
    /// Rough 95% uncertainty radius in meters.
    var radiusMeters: Double
    var sampleCount: Int
    var method: Method
    var confidence: Confidence
    var source: SignalSource
}

/// Estimates where each mesh node (access point) is from readings taken on it.
///
/// iOS only reports the access point you're connected to, so this isn't classic multi-AP
/// triangulation. Instead, each walk sample says "I was here, on node X, at strength S".
/// Signal falls off with the log of distance, so for every candidate position on a grid the
/// locator fits `strength = a + b·log10(distance)` and keeps the position that fits best.
enum AccessPointLocator {
    static let minSamples = 4
    static let minFitSamples = 8
    /// Below this share of explained variance, the fit is noise and the centroid is used.
    static let minFitR2 = 0.2
    /// How far beyond the walked area the node may be placed.
    static let searchPadding = 15.0
    static let maxGridCells = 120.0
    static let minRadius = 3.0
    static let maxRadius = 50.0
    /// Use Apple strength for a node when at least this share of its samples have it.
    static let appleShareThreshold = 0.6
    /// 95th percentile of chi-square with 2 degrees of freedom (the x/y position).
    static let chiSquare95TwoDoF = 5.99

    /// Groups BSSIDs that differ only in the last octet: one node's 2.4 GHz, 5 GHz and
    /// backhaul radios. Nil for malformed or all-zero BSSIDs.
    static func nodeKey(for bssid: String) -> String? {
        let parts = bssid.lowercased().split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 6,
              parts.allSatisfy({ (1...2).contains($0.count) && Int($0, radix: 16) != nil }) else { return nil }
        let octets = parts.map { $0.count == 1 ? "0" + $0 : String($0) }
        guard octets.contains(where: { $0 != "00" }) else { return nil }
        return octets.prefix(5).joined(separator: ":")
    }

    /// Estimates for every node with enough samples, labeled "Node 1", "Node 2"… in the order
    /// they were first seen, so labels stay put as a recording grows.
    static func locate(_ samples: [LocatorSample]) -> [AccessPointEstimate] {
        var order: [String] = []
        var groups: [String: [LocatorSample]] = [:]
        for sample in samples {
            guard let key = nodeKey(for: sample.bssid) else { continue }
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(sample)
        }
        return order.enumerated().compactMap { index, key in
            locateNode(key: key, label: "Node \(index + 1)", samples: groups[key] ?? [])
        }
    }

    static func locateNode(key: String, label: String, samples: [LocatorSample]) -> AccessPointEstimate? {
        // Mixing Apple strength and latency scores would distort the distance model, so pick one.
        let withApple = samples.filter { ($0.appleScore ?? 0) > 0 }
        let source: AccessPointEstimate.SignalSource
        let scored: [(LocatorSample, Double)]
        if !samples.isEmpty, Double(withApple.count) / Double(samples.count) >= appleShareThreshold {
            source = .appleStrength
            scored = withApple.map { ($0, $0.appleScore!) }
        } else {
            source = .latency
            scored = samples.compactMap { s in s.linkScore.map { (s, $0) } }
        }
        guard scored.count >= minSamples else { return nil }

        let n = Double(scored.count)
        let projection = LocalProjection(originLatitude: scored.reduce(0) { $0 + $1.0.latitude } / n,
                                         originLongitude: scored.reduce(0) { $0 + $1.0.longitude } / n)
        let points = scored.map { sample, score in
            let p = projection.project(latitude: sample.latitude, longitude: sample.longitude)
            return Point(x: p.x, y: p.y, score: score)
        }

        var method = AccessPointEstimate.Method.weightedCentroid
        var position: (x: Double, y: Double)
        var radius: Double
        var r2: Double?
        if points.count >= minFitSamples, let fit = pathLossFit(points), fit.r2 >= minFitR2, !fit.atEdge {
            method = .pathLossFit
            position = (fit.x, fit.y)
            radius = fit.radius
            r2 = fit.r2
        } else {
            let centroid = weightedCentroid(points)
            position = (centroid.x, centroid.y)
            radius = centroid.radius
        }
        radius = min(max(radius, minRadius), maxRadius)

        let confidence: AccessPointEstimate.Confidence
        if method == .pathLossFit, (r2 ?? 0) >= 0.5, radius <= 6, points.count >= 20 {
            confidence = .high
        } else if radius <= 12, points.count >= 10 {
            confidence = .medium
        } else {
            confidence = .low
        }

        let coordinate = projection.unproject(x: position.x, y: position.y)
        var bssids: [String] = []
        for sample in samples where !bssids.contains(sample.bssid.lowercased()) {
            bssids.append(sample.bssid.lowercased())
        }
        return AccessPointEstimate(
            id: key, label: label, bssids: bssids,
            latitude: coordinate.latitude, longitude: coordinate.longitude,
            radiusMeters: radius, sampleCount: points.count,
            method: method, confidence: confidence, source: source
        )
    }

    struct Point { let x: Double; let y: Double; let score: Double }

    struct Fit { let x: Double; let y: Double; let radius: Double; let r2: Double; let atEdge: Bool }

    /// Grid search for the position whose log-distance model best explains the scores.
    static func pathLossFit(_ points: [Point]) -> Fit? {
        let n = Double(points.count)
        let meanScore = points.reduce(0) { $0 + $1.score } / n
        let totalVariance = points.reduce(0) { $0 + ($1.score - meanScore) * ($1.score - meanScore) }
        guard totalVariance > 0 else { return nil }
        let sumS = points.reduce(0) { $0 + $1.score }
        let sumSS = points.reduce(0) { $0 + $1.score * $1.score }

        let minX = points.map(\.x).min()! - searchPadding, maxX = points.map(\.x).max()! + searchPadding
        let minY = points.map(\.y).min()! - searchPadding, maxY = points.map(\.y).max()! + searchPadding
        let step = max(1, max(maxX - minX, maxY - minY) / maxGridCells)

        var cells: [(x: Double, y: Double, sse: Double)] = []
        var best: (x: Double, y: Double, sse: Double)?
        var y = minY
        while y <= maxY {
            var x = minX
            while x <= maxX {
                var sumL = 0.0, sumLL = 0.0, sumLS = 0.0
                for p in points {
                    // Closer than a meter, GPS error dominates.
                    let l = log10(max(hypot(p.x - x, p.y - y), 1))
                    sumL += l
                    sumLL += l * l
                    sumLS += l * p.score
                }
                let denominator = n * sumLL - sumL * sumL
                if denominator > 1e-9 {
                    let slope = (n * sumLS - sumL * sumS) / denominator
                    // Signal must weaken with distance; otherwise this spot can't be the node.
                    if slope < 0 {
                        let intercept = (sumS - slope * sumL) / n
                        let sse = sumSS - 2 * intercept * sumS - 2 * slope * sumLS
                            + n * intercept * intercept + 2 * intercept * slope * sumL + slope * slope * sumLL
                        let cell = (x: x, y: y, sse: max(sse, 0))
                        cells.append(cell)
                        if cell.sse < best?.sse ?? .infinity { best = cell }
                    }
                }
                x += step
            }
            y += step
        }
        guard let best else { return nil }

        // Positions whose fit is statistically indistinguishable from the best one.
        let noiseVariance = best.sse / max(n - 4, 1)
        let threshold = best.sse + chiSquare95TwoDoF * noiseVariance
        let spread = cells.lazy.filter { $0.sse <= threshold }.map { hypot($0.x - best.x, $0.y - best.y) }.max() ?? 0

        let atEdge = best.x - minX < step || maxX - best.x < step || best.y - minY < step || maxY - best.y < step
        return Fit(x: best.x, y: best.y, radius: spread + step / 2, r2: 1 - best.sse / totalVariance, atEdge: atEdge)
    }

    /// Strength-weighted average of the strongest ~30% of positions.
    static func weightedCentroid(_ points: [Point]) -> (x: Double, y: Double, radius: Double) {
        let strongest = points.sorted { $0.score > $1.score }
            .prefix(max(3, Int((Double(points.count) * 0.3).rounded(.up))))
        let weights = strongest.map { pow(max($0.score, 1), 3) }
        let total = weights.reduce(0, +)
        let x = zip(strongest, weights).reduce(0) { $0 + $1.0.x * $1.1 } / total
        let y = zip(strongest, weights).reduce(0) { $0 + $1.0.y * $1.1 } / total
        let variance = zip(strongest, weights).reduce(0) {
            $0 + $1.1 * ((($1.0.x - x) * ($1.0.x - x)) + (($1.0.y - y) * ($1.0.y - y)))
        } / total
        return (x, y, 2 * sqrt(variance))
    }
}

extension WiFiMap {
    /// Connected samples with a BSSID, oldest first, for `AccessPointLocator`.
    func locatorSamples() -> [LocatorSample] {
        samples.sorted { $0.timestamp < $1.timestamp }.compactMap { sample in
            guard sample.connected, let bssid = sample.bssid else { return nil }
            let metrics = sample.metrics
            return LocatorSample(latitude: sample.latitude, longitude: sample.longitude, bssid: bssid,
                                 appleScore: SignalScoring.appleScore(metrics),
                                 linkScore: SignalScoring.linkScore(metrics))
        }
    }
}

extension AccessPointLocator {
    /// The grid search takes a few milliseconds per node; keep it off the main thread.
    static func locateInBackground(_ samples: [LocatorSample]) async -> [AccessPointEstimate] {
        await Task.detached(priority: .userInitiated) { locate(samples) }.value
    }

    /// Plain-language direction, e.g. "north-east", for a bearing in degrees from north.
    static func compassDirection(degrees: Double) -> String {
        let names = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
        let index = Int(((degrees.truncatingRemainder(dividingBy: 360) + 360 + 22.5) / 45).rounded(.down)) % 8
        return names[index]
    }
}
