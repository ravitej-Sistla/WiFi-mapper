import Foundation
import Observation

/// Continuously measures the current Wi-Fi. Home shows the latest reading; a
/// recording subscribes through `onReading` and pairs each reading with GPS.
@MainActor
@Observable
final class SignalMonitor {
    struct Reading: Equatable {
        var timestamp: Date
        var ssid: String?
        var bssid: String?
        var gateway: String?
        var metrics: SampleMetrics
    }

    private(set) var reading: Reading?
    private(set) var isRunning = false

    /// Called on every new reading; set by an active recording.
    @ObservationIgnored var onReading: ((Reading) -> Void)?
    var hasSubscriber: Bool { onReading != nil }

    @ObservationIgnored private let path: NetworkPathService
    @ObservationIgnored private let probe = LinkQualityProbe()
    @ObservationIgnored private var loopTask: Task<Void, Never>?
    @ObservationIgnored var pause: Duration = .milliseconds(1500)

    init(path: NetworkPathService) {
        self.path = path
    }

    func start() {
        guard loopTask == nil else { return }
        isRunning = true
        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.measureOnce()
                try? await Task.sleep(for: self.pause)
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        isRunning = false
    }

    func measureOnce() async {
        guard path.hasPath else { return }
        guard path.kind == .wifi else {
            publish(Reading(timestamp: .now, ssid: nil, bssid: nil, gateway: nil, metrics: .disconnected))
            return
        }

        let started = Date.now
        let settings = ProbeSettings.load()
        async let info = WiFiInfoService.fetchCurrent()
        let gateway = settings.gatewayOverride ?? GatewayResolver.guessedGateway()
        // No router to probe means link quality is unknown, not zero.
        var link: LinkQualityResult?
        if let gateway {
            link = await probe.measure(host: gateway, throughputURL: settings.throughputURL)
        }
        let snapshot = await info

        // The path may have dropped while probing; that's a dead zone, not a slow link.
        guard path.kind == .wifi else {
            publish(Reading(timestamp: .now, ssid: nil, bssid: nil, gateway: nil, metrics: .disconnected))
            return
        }

        let metrics = SampleMetrics(
            connected: true,
            appleStrength: snapshot?.signalStrength,
            rttMs: link?.rttMs,
            jitterMs: link?.jitterMs,
            lossPct: link?.lossPct,
            throughputMbps: link?.throughputMbps
        )
        publish(Reading(timestamp: started, ssid: snapshot?.ssid, bssid: snapshot?.bssid, gateway: gateway, metrics: metrics))
    }

    private func publish(_ reading: Reading) {
        self.reading = reading
        onReading?(reading)
    }
}
