import SwiftUI

/// One recording drawn under both scoring modes, with numbers to judge them by.
struct CompareModesView: View {
    let map: WiFiMap

    var body: some View {
        let metrics = map.samples.map(\.metrics)
        let stats = ScoringMode.allCases.map { ModeStats(mode: $0, metrics: metrics) }
        let connected = metrics.filter(\.connected)
        let appleCoverage = connected.isEmpty
            ? nil
            : Double(connected.filter { SignalScoring.appleScore($0) != nil }.count) / Double(connected.count)
        let agreement = modeAgreement(metrics)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { maps }
                        .frame(minWidth: 700)
                    VStack(spacing: 12) { maps }
                }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        Text("")
                        ForEach(stats, id: \.mode) { Text($0.mode.title).font(.headline) }
                    }
                    Divider()
                    statRow("Samples scored", stats) { "\($0.scoredCount) / \($0.totalCount)" }
                    statRow("Average", stats) { Format.score($0.mean) }
                    statRow("Range", stats) { "\(Format.score($0.minimum))–\(Format.score($0.maximum))" }
                    statRow("Spread (std dev)", stats) { Format.number($0.spread, digits: 1) }
                    statRow("vs. latency", stats) { Format.correlation($0.latencyCorrelation) }
                    statRow("vs. throughput", stats) { Format.correlation($0.throughputCorrelation) }
                }
                .font(.callout.monospacedDigit())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple strength reported in \(Format.percent(appleCoverage)) of connected samples.")
                    Text("Agreement between modes: \(Format.correlation(agreement)).")
                }
                .font(.callout)

                Text("""
                    How to judge: look for the map that matches spots you know are good or bad (for example, \
                    where streaming stalls). Larger spread means the mode separates strong and weak spots more \
                    clearly. Correlation with latency should be negative and with throughput positive; \
                    "Link quality" is built from latency, so it will always correlate more strongly with it.
                    """)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Compare modes")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var maps: some View {
        ForEach(ScoringMode.allCases) { mode in
            VStack(alignment: .leading, spacing: 4) {
                Text(mode.title).font(.headline)
                HeatmapMapView(points: map.heatPoints(mode: mode))
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func statRow(_ title: String, _ stats: [ModeStats], value: @escaping (ModeStats) -> String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            ForEach(stats, id: \.mode) { Text(value($0)) }
        }
    }

    private func modeAgreement(_ metrics: [SampleMetrics]) -> Double? {
        let pairs = metrics.compactMap { m -> (Double, Double)? in
            guard let hybrid = ScoringMode.hybrid.score(m), let link = ScoringMode.linkQuality.score(m) else { return nil }
            return (hybrid, link)
        }
        return Stats.pearson(pairs.map(\.0), pairs.map(\.1))
    }
}
