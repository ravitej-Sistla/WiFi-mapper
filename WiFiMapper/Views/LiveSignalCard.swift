import SwiftUI

/// Hero card with the live strength of the current Wi-Fi under the default scoring mode.
struct LiveSignalCard: View {
    @Environment(SignalMonitor.self) private var monitor
    @Environment(NetworkPathService.self) private var path
    @AppStorage(AppSettingsKey.scoringMode) private var mode = ScoringMode.fallback

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("LIVE SIGNAL")
                    .font(.caption.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                if path.kind == .wifi, monitor.reading?.metrics.connected == true {
                    HStack(spacing: 6) {
                        PulsingDot(color: .green)
                        Text("LIVE").font(.caption2.weight(.bold)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.12), in: Capsule())
                }
            }

            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                Brand.heroGradient
                // Soft glow so the card doesn't read as a flat block.
                Circle()
                    .fill(Brand.teal.opacity(0.35))
                    .frame(width: 260)
                    .blur(radius: 70)
                    .offset(x: 140, y: -90)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Brand.navy.opacity(0.35), radius: 18, y: 8)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var content: some View {
        if !path.hasPath {
            placeholder(icon: "antenna.radiowaves.left.and.right", title: "Checking connection…", detail: nil, spinning: true)
        } else if path.kind != .wifi {
            placeholder(icon: "wifi.slash", title: "Not on Wi-Fi", detail: "Connect to Wi-Fi to see signal strength.", spinning: false)
        } else if let reading = monitor.reading, reading.metrics.connected {
            ReadingView(reading: reading, mode: mode)
        } else {
            placeholder(icon: "wifi", title: "Measuring…", detail: "Timing your router's responses.", spinning: true)
        }
    }

    private func placeholder(icon: String, title: String, detail: String?, spinning: Bool) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(.white.opacity(0.1), in: Circle())
                .symbolEffect(.pulse, isActive: spinning)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.bold()).foregroundStyle(.white)
                if let detail {
                    Text(detail).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .padding(.vertical, 8)
    }
}

private struct ReadingView: View {
    let reading: SignalMonitor.Reading
    let mode: ScoringMode

    var body: some View {
        let metrics = reading.metrics
        let score = mode.score(metrics)
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 20) {
                SignalRing(score: score, lineWidth: 11, trackColor: .white.opacity(0.12), caption: "of 100")
                    .frame(width: 118, height: 118)
                VStack(alignment: .leading, spacing: 6) {
                    Text(score.map { SignalQuality(score: $0).label } ?? "No data")
                        .font(.title.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(SignalColor.color(for: score))
                    Label(reading.ssid ?? "Network name unavailable", systemImage: "wifi")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let bssid = reading.bssid {
                        Label(bssid, systemImage: "point.3.connected.trianglepath.dotted")
                            .font(.caption.monospaced())
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                    Text("\(mode.title) score")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.12), in: Capsule())
                }
            }

            HStack(spacing: 8) {
                tile("Latency", Format.number(metrics.rttMs, digits: 1), unit: "ms", icon: "stopwatch")
                tile("Jitter", Format.number(metrics.jitterMs, digits: 1), unit: "ms", icon: "waveform.path")
                tile("Loss", Format.number(metrics.lossPct), unit: "%", icon: "exclamationmark.arrow.circlepath")
                if let throughput = metrics.throughputMbps {
                    tile("Speed", Format.number(throughput, digits: 0), unit: "Mbps", icon: "arrow.down.circle")
                } else {
                    tile("Apple", Format.percent(metrics.appleStrength.flatMap { $0 > 0 ? $0 : nil }), unit: "", icon: "cellularbars")
                }
            }

            if mode == .hybrid && SignalScoring.appleScore(metrics) == nil && SignalScoring.linkScore(metrics) != nil {
                note("Apple strength unavailable — using link quality only.", icon: "info.circle", color: .white.opacity(0.7))
            }
            if reading.gateway == nil {
                note("Couldn't find your router. Set it in Settings.", icon: "exclamationmark.triangle.fill", color: .orange)
            }
        }
    }

    private func tile(_ title: String, _ value: String, unit: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(Brand.teal)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.headline.monospacedDigit()).foregroundStyle(.white)
                Text(unit).font(.caption2).foregroundStyle(.white.opacity(0.6))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func note(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(color)
    }
}
