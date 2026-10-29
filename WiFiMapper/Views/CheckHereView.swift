import SwiftData
import SwiftUI

/// Without recording: what do saved maps say about the spot you're standing on?
struct CheckHereView: View {
    @Query(sort: \WiFiMap.updatedAt, order: .reverse) private var maps: [WiFiMap]
    @Environment(LocationService.self) private var location
    @Environment(Router.self) private var router
    @AppStorage(AppSettingsKey.scoringMode) private var mode = ScoringMode.fallback

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LiveSignalCard()

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Saved maps at this spot")
                    results
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .brandBackground()
        .navigationTitle("Check Here")
    }

    @ViewBuilder
    private var results: some View {
        if let here = location.location {
            let matches = matches(latitude: here.coordinate.latitude, longitude: here.coordinate.longitude)
            if matches.isEmpty {
                message(icon: "mappin.slash", title: "No maps cover this spot",
                        detail: "Record a walk here to add it to a map.")
            }
            ForEach(matches, id: \.map.persistentModelID) { match in
                Button {
                    router.show(.map(match.map))
                } label: {
                    row(match.map, estimate: match.estimate)
                }
                .buttonStyle(.plain)
            }
        } else if location.isDenied {
            message(icon: "location.slash", title: "Location access is off",
                    detail: "Your spot can't be matched to a map without it.")
        } else {
            HStack(spacing: 12) {
                ProgressView()
                Text("Getting your location…").foregroundStyle(.secondary)
            }
            .card()
        }
    }

    private func matches(latitude: Double, longitude: Double) -> [(map: WiFiMap, estimate: HeatEstimate)] {
        maps.compactMap { map in
            IDWInterpolator(points: map.heatPoints(mode: mode))
                .estimate(latitude: latitude, longitude: longitude)
                .map { (map, $0) }
        }
    }

    private func row(_ map: WiFiMap, estimate: HeatEstimate) -> some View {
        HStack(spacing: 14) {
            SignalRing(score: estimate.value, lineWidth: 5, valueFont: .system(size: 15, weight: .bold, design: .rounded))
                .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(map.name).font(.headline).lineLimit(1)
                    Pill(text: "v\(map.version)")
                }
                Text("\(SignalQuality(score: estimate.value).label) here · nearest sample \(Format.number(estimate.nearestDistance, unit: "m"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .card(padding: 14)
    }

    private func message(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            IconTile(systemName: icon, color: .gray, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
        .card(padding: 14)
    }
}
