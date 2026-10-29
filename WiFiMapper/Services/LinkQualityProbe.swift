import Foundation
import Network

struct LinkQualityResult: Equatable {
    var rttMs: Double?
    var jitterMs: Double?
    var lossPct: Double
    var throughputMbps: Double?

    static let unreachable = LinkQualityResult(rttMs: nil, jitterMs: nil, lossPct: 100, throughputMbps: nil)
}

/// Measures Wi-Fi link quality by timing TCP handshakes to the router. A weak radio
/// link shows up as higher and more variable round trips and, eventually, lost probes.
@MainActor
final class LinkQualityProbe {
    /// Routers usually answer on at least one of these (web admin, HTTPS, DNS).
    /// A refused connection still counts, since the RST proves the round trip.
    static let candidatePorts: [UInt16] = [80, 443, 53]

    var attempts = 5
    var timeout: TimeInterval = 1.0
    private var cachedPort: (host: String, port: UInt16)?

    func measure(host: String, throughputURL: URL? = nil) async -> LinkQualityResult {
        guard let port = await resolvePort(host: host) else { return .unreachable }

        var rtts: [Double] = []
        for _ in 0..<attempts {
            if let rtt = await Self.handshakeRTT(host: host, port: port, timeout: timeout) {
                rtts.append(rtt)
            }
        }
        let lossPct = 100 * Double(attempts - rtts.count) / Double(attempts)
        let jitter: Double? = rtts.count > 1
            ? zip(rtts, rtts.dropFirst()).map { abs($0 - $1) }.reduce(0, +) / Double(rtts.count - 1)
            : nil

        var throughput: Double?
        if let throughputURL, !rtts.isEmpty {
            throughput = await Self.throughput(url: throughputURL)
        }
        return LinkQualityResult(rttMs: Stats.median(rtts), jitterMs: jitter, lossPct: lossPct, throughputMbps: throughput)
    }

    private func resolvePort(host: String) async -> UInt16? {
        if let cachedPort, cachedPort.host == host { return cachedPort.port }
        for port in Self.candidatePorts {
            if await Self.handshakeRTT(host: host, port: port, timeout: timeout) != nil {
                cachedPort = (host, port)
                return port
            }
        }
        return nil
    }

    /// Milliseconds until the router answers a TCP SYN (accept or refuse), or nil on timeout.
    nonisolated static func handshakeRTT(host: String, port: UInt16, timeout: TimeInterval) async -> Double? {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .wifi
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
        let queue = DispatchQueue(label: "wifimapper.probe")
        let once = ResumeOnce()

        return await withCheckedContinuation { continuation in
            let start = DispatchTime.now().uptimeNanoseconds
            let finish: @Sendable (Bool) -> Void = { success in
                guard once.claim() else { return }
                let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                connection.cancel()
                continuation.resume(returning: success ? elapsedMs : nil)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(true)
                case .waiting(let error), .failed(let error):
                    if case .posix(let code) = error, code == .ECONNREFUSED {
                        finish(true)
                    } else if case .failed = state {
                        finish(false)
                    }
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
    }

    /// Download speed over Wi-Fi only, in Mbps.
    nonisolated static func throughput(url: URL, timeout: TimeInterval = 6) async -> Double? {
        let config = URLSessionConfiguration.ephemeral
        config.allowsCellularAccess = false
        config.timeoutIntervalForRequest = timeout
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        let start = Date()
        guard let result = try? await session.data(from: url),
              (result.1 as? HTTPURLResponse)?.statusCode == 200, !result.0.isEmpty else { return nil }
        let seconds = max(Date().timeIntervalSince(start), 0.001)
        return Double(result.0.count) * 8 / seconds / 1_000_000
    }
}

/// Guards a continuation against being resumed twice (state change vs. timeout).
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
