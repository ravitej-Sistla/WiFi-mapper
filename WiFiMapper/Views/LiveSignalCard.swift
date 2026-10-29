import SwiftUI

/// Live strength of the current Wi-Fi under the default scoring mode, plus the raw values.
struct LiveSignalCard: View {
    @Environment(SignalMonitor.self) private var monitor
    @Environment(NetworkPathService.self) private var path
    @AppStorage(AppSettingsKey.scoringMode) private var mode = ScoringMode.fallback

    var body: some View {
        if !path.hasPath {
            ProgressView("Checking connection…")
                .frame(maxWidth: .infinity)
        } else if path.kind != .wifi {
            VStack(alignment: .leading, spacing: 6) {
                Label("Not on Wi-Fi", systemImage: "wifi.slash")
                    .font(.headline)
                Text("Connect to Wi-Fi to see signal strength.")
                    .foregroundStyle(.secondary)
            }
        } else if let reading = monitor.reading, reading.metrics.connected {
            ReadingView(reading: reading, mode: mode)
        } else {
            ProgressView("Measuring…")
                .frame(maxWidth: .infinity)
        }
    }
}

private struct ReadingView: View {
    let reading: SignalMonitor.Reading
    let mode: ScoringMode

    var body: some View {
        let metrics = reading.metrics
        let score = mode.score(metrics)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 20) {
                ScoreGauge(score: score)
                VStack(alignment: .leading, spacing: 2) {
                    Text(score.map { SignalQuality(score: $0).label } ?? "No measurement")
                        .font(.title2.bold())
                        .foregroundStyle(SignalColor.color(for: score))
                    Text(reading.ssid ?? "Network name unavailable")
                        .font(.subheadline)
                    if let bssid = reading.bssid {
                        Text("Node \(bssid)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Text("\(mode.title) score")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow {
                    metric("Apple strength", Format.percent(metrics.appleStrength.flatMap { $0 > 0 ? $0 : nil }))
                    metric("Latency", Format.number(metrics.rttMs, digits: 1, unit: "ms"))
                }
                GridRow {
                    metric("Jitter", Format.number(metrics.jitterMs, digits: 1, unit: "ms"))
                    metric("Loss", Format.number(metrics.lossPct, unit: "%"))
                }
                if let throughput = metrics.throughputMbps {
                    GridRow {
                        metric("Throughput", Format.number(throughput, digits: 1, unit: "Mbps"))
                    }
                }
            }

            if mode == .hybrid && SignalScoring.appleScore(metrics) == nil {
                Label("Apple strength unavailable — using link quality only.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if reading.gateway == nil {
                Label("Couldn't find your router. Set it in Settings.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.monospacedDigit())
        }
    }
}

struct ScoreGauge: View {
    let score: Double?

    var body: some View {
        Gauge(value: score ?? 0, in: 0...100) {
            EmptyView()
        } currentValueLabel: {
            Text(Format.score(score))
        }
        .gaugeStyle(.accessoryCircular)
        .tint(Gradient(colors: [.red, .yellow, .green]))
        .scaleEffect(1.3)
        .frame(width: 70, height: 70)
    }
}
