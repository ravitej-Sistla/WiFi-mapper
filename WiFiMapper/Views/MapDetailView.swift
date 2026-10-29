import SwiftUI

/// A saved map with your live position and the expected signal where you stand.
struct MapDetailView: View {
    let map: WiFiMap

    @Environment(LocationService.self) private var location
    @Environment(SignalMonitor.self) private var monitor
    @Environment(NetworkPathService.self) private var path
    @Environment(Router.self) private var router
    @AppStorage(AppSettingsKey.scoringMode) private var defaultMode = ScoringMode.fallback
    @State private var selectedMode: ScoringMode?
    @State private var showDots = false
    @State private var renaming: WiFiMap?
    @State private var newName = ""

    private var mode: ScoringMode { selectedMode ?? defaultMode }

    var body: some View {
        let points = map.heatPoints(mode: mode)
        ZStack(alignment: .bottom) {
            HeatmapMapView(points: points, showSampleDots: showDots)
                .ignoresSafeArea(edges: .bottom)
            hereCard(interpolator: IDWInterpolator(points: points))
        }
        .navigationTitle(map.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        router.show(.record(.update(map)))
                    } label: {
                        Label("Continue recording (update)", systemImage: "record.circle")
                    }
                    Button {
                        router.show(.record(.newVersion(of: map)))
                    } label: {
                        Label("Record as new version", systemImage: "square.on.square")
                    }
                    Button {
                        router.show(.compare(map))
                    } label: {
                        Label("Compare scoring modes", systemImage: "rectangle.split.2x1")
                    }
                    Toggle(isOn: $showDots) {
                        Label("Show sample dots", systemImage: "circle.grid.3x3")
                    }
                    Button {
                        newName = map.name
                        renaming = map
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Map actions")
            }
        }
        .renameAlert(map: $renaming, name: $newName)
    }

    private func hereCard(interpolator: IDWInterpolator) -> some View {
        let estimate = location.location.flatMap {
            interpolator.estimate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
        let live = path.kind == .wifi ? monitor.reading.flatMap { mode.score($0.metrics) } : nil

        return VStack(spacing: 10) {
            Picker("Scoring mode", selection: Binding(get: { mode }, set: { selectedMode = $0 })) {
                ForEach(ScoringMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack(alignment: .top) {
                VStack {
                    Text(Format.score(estimate?.value))
                        .font(.largeTitle.bold().monospacedDigit())
                        .foregroundStyle(SignalColor.color(for: estimate?.value))
                    Text(hereCaption(estimate: estimate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                VStack {
                    Text(Format.score(live))
                        .font(.largeTitle.bold().monospacedDigit())
                        .foregroundStyle(SignalColor.color(for: live))
                    Text(path.kind == .wifi ? "Live now" : "Not on Wi-Fi")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }

            Text("v\(map.version) · \(map.samples.count) samples · updated \(map.updatedAt.formatted(.relative(presentation: .named)))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: 500)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    private func hereCaption(estimate: HeatEstimate?) -> String {
        if location.location == nil { return "Waiting for location" }
        guard let estimate else { return "Outside the mapped area" }
        return "Map here (nearest sample \(Format.number(estimate.nearestDistance, unit: "m")))"
    }
}
