#if DEBUG
import Foundation
import SwiftData

/// Debug builds only: launch with `-demoData` to add a sample map for checking the UI
/// in the simulator, which can't record real Wi-Fi readings.
enum DemoData {
    static let center = (latitude: 37.33467, longitude: -122.00898)

    @MainActor
    static func seedIfRequested(_ context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("-demoData"),
              (try? context.fetchCount(FetchDescriptor<WiFiMap>())) == 0 else { return }

        let map = WiFiMap(name: "Home & garden")
        context.insert(map)
        // Main router plus a satellite node; each spot connects to the nearer one.
        let nodes = [(x: -8.0, y: 6.0, bssid: "a4:2b:b0:1c:3e:7f", backhaulMs: 0.0),
                     (x: 20.0, y: -12.0, bssid: "a4:2b:b0:5d:91:21", backhaulMs: 4.0)]
        let meter = 1 / 111_132.0
        let lonMeter = meter / cos(center.latitude * .pi / 180)
        var x = -30.0
        while x <= 30 {
            var y = -24.0
            while y <= 24 {
                let node = nodes.min { hypot(x - $0.x, y - $0.y) < hypot(x - $1.x, y - $1.y) }!
                let distance = hypot(x - node.x, y - node.y)
                let rtt = 3 + node.backhaulMs + pow(distance / 5, 2) + Double.random(in: 0...3)
                let metrics = SampleMetrics(connected: rtt < 120, appleStrength: nil, rttMs: rtt,
                                            jitterMs: rtt / 8, lossPct: rtt > 60 ? 20 : 0, throughputMbps: nil)
                map.samples.append(SignalSample(
                    timestamp: .now, latitude: center.latitude + y * meter, longitude: center.longitude + x * lonMeter,
                    horizontalAccuracy: 5, ssid: "Home Mesh", bssid: node.bssid, metrics: metrics))
                y += 4
            }
            x += 4
        }
        let older = WiFiMap(name: "Backyard", version: 2)
        older.updatedAt = .now.addingTimeInterval(-3 * 86_400)
        context.insert(older)
        try? context.save()
    }

    /// `-demoScreen map|compare|record|checkHere|settings` opens that screen at launch.
    @MainActor
    static func requestedRoute(_ context: ModelContext) -> Route? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-demoScreen"), index + 1 < args.count else { return nil }
        var newest = FetchDescriptor<WiFiMap>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        newest.fetchLimit = 1
        let map = (try? context.fetch(newest))?.first
        switch args[index + 1] {
        case "map": return map.map { .map($0) }
        case "compare": return map.map { .compare($0) }
        case "record": return .record(.newMap)
        case "checkHere": return .checkHere
        case "settings": return .settings
        default: return nil
        }
    }
}
#endif
