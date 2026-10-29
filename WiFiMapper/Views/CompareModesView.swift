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
            VStack(alignment: .leading, spacing: 20) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { maps(stats) }
                        .frame(minWidth: 700)
                    VStack(spacing: 12) { maps(stats) }
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Statistics")
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                        GridRow {
                            Text("")
                            ForEach(stats, id: \.mode) { Text($0.mode.title).font(.subheadline.bold()) }
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
                    .card()
                }

                HStack(spacing: 12) {
                    summaryTile("Apple strength reported", Format.percent(appleCoverage), icon: "cellularbars")
                    summaryTile("Agreement between modes", Format.correlation(agreement), icon: "arrow.triangle.merge")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("How to judge", systemImage: "lightbulb.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(Brand.blue)
                    Text("""
                        Look for the map that matches spots you know are good or bad (for example, \
                        where streaming stalls). Larger spread means the mode separates strong and weak spots more \
                        clearly. Correlation with latency should be negative and with throughput positive; \
                        "Link quality" is built from latency, so it will always correlate more strongly with it.
                        """)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .card()
            }
            .padding(16)
        }
        .brandBackground()
        .navigationTitle("Compare modes")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func maps(_ stats: [ModeStats]) -> some View {
        ForEach(stats, id: \.mode) { stat in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(stat.mode.title).font(.headline)
                    Spacer()
                    Text("avg \(Format.score(stat.mean))")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(SignalColor.color(for: stat.mean))
                }
                HeatmapMapView(points: map.heatPoints(mode: stat.mode))
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                LegendBar()
            }
            .card(padding: 12)
        }
    }

    private func statRow(_ title: String, _ stats: [ModeStats], value: @escaping (ModeStats) -> String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            ForEach(stats, id: \.mode) { Text(value($0)) }
        }
    }

    private func summaryTile(_ title: String, _ value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(Brand.teal)
            Text(value).font(.title2.bold().monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .card(padding: 14)
    }

    private func modeAgreement(_ metrics: [SampleMetrics]) -> Double? {
        let pairs = metrics.compactMap { m -> (Double, Double)? in
            guard let hybrid = ScoringMode.hybrid.score(m), let link = ScoringMode.linkQuality.score(m) else { return nil }
            return (hybrid, link)
        }
        return Stats.pearson(pairs.map(\.0), pairs.map(\.1))
    }
}
