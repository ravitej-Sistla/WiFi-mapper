import SwiftData
import SwiftUI

/// Without recording: what do saved maps say about the spot you're standing on?
struct CheckHereView: View {
    @Query(sort: \WiFiMap.updatedAt, order: .reverse) private var maps: [WiFiMap]
    @Environment(LocationService.self) private var location
    @Environment(Router.self) private var router
    @AppStorage(AppSettingsKey.scoringMode) private var mode = ScoringMode.fallback

    var body: some View {
        List {
            Section("Live signal") {
                LiveSignalCard()
            }

            Section("Saved maps at this spot") {
                if let here = location.location {
                    let matches = matches(latitude: here.coordinate.latitude, longitude: here.coordinate.longitude)
                    if matches.isEmpty {
                        Text("None of your saved maps cover this spot.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(matches, id: \.map.persistentModelID) { match in
                        Button {
                            router.show(.map(match.map))
                        } label: {
                            row(match.map, estimate: match.estimate)
                        }
                        .foregroundStyle(.primary)
                    }
                } else if location.isDenied {
                    Text("Location access is off, so your spot can't be matched to a map.")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView("Getting your location…")
                }
            }
        }
        .navigationTitle("Check Here")
    }

    private func matches(latitude: Double, longitude: Double) -> [(map: WiFiMap, estimate: HeatEstimate)] {
        maps.compactMap { map in
            IDWInterpolator(points: map.heatPoints(mode: mode))
                .estimate(latitude: latitude, longitude: longitude)
                .map { (map, $0) }
        }
    }

    private func row(_ map: WiFiMap, estimate: HeatEstimate) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(map.name) · v\(map.version)").font(.headline).lineLimit(1)
                Text("Updated \(map.updatedAt.formatted(.relative(presentation: .named))) · nearest sample \(Format.number(estimate.nearestDistance, unit: "m"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Format.score(estimate.value))
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(SignalColor.color(for: estimate.value))
        }
    }
}
