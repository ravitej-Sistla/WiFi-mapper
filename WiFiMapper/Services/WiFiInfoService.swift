import Foundation
import Network
import NetworkExtension
import Observation

enum ConnectionKind {
    case wifi, cellular, other, offline
}

/// Tracks whether the device is on Wi-Fi right now.
@MainActor
@Observable
final class NetworkPathService {
    private(set) var kind: ConnectionKind = .offline
    /// False until the first path update arrives, so we don't report "offline" at launch.
    private(set) var hasPath = false

    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let kind = Self.kind(for: path)
            Task { @MainActor in
                self?.kind = kind
                self?.hasPath = true
            }
        }
        monitor.start(queue: DispatchQueue(label: "wifimapper.path"))
    }

    nonisolated private static func kind(for path: Network.NWPath) -> ConnectionKind {
        // Being associated with Wi-Fi counts even if the internet beyond the router is down.
        if path.usesInterfaceType(.wifi) || path.availableInterfaces.contains(where: { $0.type == .wifi }) {
            return .wifi
        }
        guard path.status == .satisfied else { return .offline }
        return path.usesInterfaceType(.cellular) ? .cellular : .other
    }
}

struct WiFiSnapshot {
    var ssid: String?
    var bssid: String?
    /// 0...1. Apple documents this as best-effort; it may be 0 outside hotspot-helper apps.
    var signalStrength: Double?
}

enum WiFiInfoService {
    /// Requires the "Access Wi-Fi Information" entitlement and location permission.
    /// Returns nil when either is missing or the device isn't on Wi-Fi.
    static func fetchCurrent() async -> WiFiSnapshot? {
        await withCheckedContinuation { continuation in
            NEHotspotNetwork.fetchCurrent { network in
                continuation.resume(returning: network.map {
                    WiFiSnapshot(ssid: $0.ssid, bssid: $0.bssid, signalStrength: $0.signalStrength)
                })
            }
        }
    }
}
