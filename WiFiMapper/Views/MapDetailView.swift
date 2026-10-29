import CoreLocation
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
    @AppStorage(AppSettingsKey.showAccessPoints) private var showAccessPoints = true
    @State private var accessPoints: [AccessPointEstimate] = []
    @State private var renaming: WiFiMap?
    @State private var newName = ""

    private var mode: ScoringMode { selectedMode ?? defaultMode }

    var body: some View {
        let points = map.heatPoints(mode: mode)
        ZStack(alignment: .bottom) {
            HeatmapMapView(points: points, showSampleDots: showDots, accessPoints: showAccessPoints ? accessPoints : [])
                .ignoresSafeArea()
            hereCard(interpolator: IDWInterpolator(points: points))
        }
        .navigationTitle(map.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
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
                    Divider()
                    Toggle(isOn: $showDots) {
                        Label("Show sample dots", systemImage: "circle.grid.3x3")
                    }
                    Toggle(isOn: $showAccessPoints) {
                        Label("Show access points", systemImage: "wifi.router")
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
        .task(id: map.samples.count) {
            accessPoints = await AccessPointLocator.locateInBackground(map.locatorSamples())
        }
    }

    private func hereCard(interpolator: IDWInterpolator) -> some View {
        let estimate = location.location.flatMap {
            interpolator.estimate(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
        }
        let live = path.kind == .wifi ? monitor.reading.flatMap { mode.score($0.metrics) } : nil

        return VStack(spacing: 14) {
            Picker("Scoring mode", selection: Binding(get: { mode }, set: { selectedMode = $0 })) {
                ForEach(ScoringMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 12) {
                gauge(score: estimate?.value, title: "Map here", detail: hereCaption(estimate: estimate), icon: "map.fill")
                gauge(score: live, title: "Live now", detail: path.kind == .wifi ? (monitor.reading?.ssid ?? "Wi-Fi") : "Not on Wi-Fi",
                      icon: "dot.radiowaves.left.and.right")
            }

            if showAccessPoints, let nearest = nearestAccessPoint {
                Label(nearest, systemImage: "wifi.router.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Brand.indigo)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            LegendBar()

            HStack(spacing: 8) {
                Pill(text: "v\(map.version)")
                Text("\(map.samples.count) samples · updated \(map.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: 520)
        .background(Brand.card.opacity(0.9), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
        .padding()
    }

    private func gauge(score: Double?, title: String, detail: String, icon: String) -> some View {
        HStack(spacing: 12) {
            SignalRing(score: score, lineWidth: 6, valueFont: .system(size: 20, weight: .bold, design: .rounded))
                .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Brand.blue)
                Text(score.map { SignalQuality(score: $0).label } ?? "—")
                    .font(.headline)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    /// "Node 1 is about 12 m north-east (±4 m)" for the closest estimated access point.
    private var nearestAccessPoint: String? {
        guard let here = location.location else {
            return accessPoints.isEmpty ? nil : "\(accessPoints.count) access point\(accessPoints.count == 1 ? "" : "s") on this map"
        }
        let nearest = accessPoints
            .map { ($0, CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: here)) }
            .min { $0.1 < $1.1 }
        guard let (estimate, distance) = nearest else { return nil }
        if distance <= estimate.radiusMeters {
            return "You're at \(estimate.label) (±\(Int(estimate.radiusMeters.rounded())) m)"
        }
        let bearing = Self.bearing(from: here.coordinate, to: CLLocationCoordinate2D(latitude: estimate.latitude, longitude: estimate.longitude))
        return "\(estimate.label) is about \(Int(distance.rounded())) m \(AccessPointLocator.compassDirection(degrees: bearing)) (±\(Int(estimate.radiusMeters.rounded())) m)"
    }

    private static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return atan2(y, x) * 180 / .pi
    }

    private func hereCaption(estimate: HeatEstimate?) -> String {
        if location.location == nil { return "Waiting for location" }
        guard let estimate else { return "Outside mapped area" }
        return "Nearest sample \(Format.number(estimate.nearestDistance, unit: "m"))"
    }
}
