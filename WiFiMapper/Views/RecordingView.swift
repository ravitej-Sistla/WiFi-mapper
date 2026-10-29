import SwiftData
import SwiftUI

/// Builds the heatmap live as you walk. Stop asks to save or discard.
struct RecordingView: View {
    let target: RecordingTarget

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SignalMonitor.self) private var monitor
    @Environment(LocationService.self) private var location
    @Environment(AdsManager.self) private var ads
    @AppStorage(AppSettingsKey.scoringMode) private var mode = ScoringMode.fallback
    @AppStorage(AppSettingsKey.showAccessPoints) private var showAccessPoints = true
    @State private var accessPoints: [AccessPointEstimate] = []
    @State private var session: RecordingSession?
    @State private var startedAt = Date.now
    @State private var showFinish = false
    @State private var name = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            HeatmapMapView(points: session?.map.heatPoints(mode: mode) ?? [], showSampleDots: true,
                           accessPoints: showAccessPoints ? accessPoints : [], followsUser: true)
                .ignoresSafeArea()
            if let session {
                controls(session)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .onAppear(perform: begin)
        .onDisappear(perform: end)
        .task(id: session?.acceptedCount ?? 0) {
            // Coalesce bursts of new samples before re-running the locator.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let map = session?.map else { return }
            let estimates = await AccessPointLocator.locateInBackground(map.locatorSamples())
            if !Task.isCancelled { accessPoints = estimates }
        }
        .alert("Save recording", isPresented: $showFinish) {
            TextField("Name", text: $name)
            Button("Save") {
                let samples = session?.acceptedCount ?? 0
                session?.finish(name: name)
                dismiss()
                ads.showInterstitialAfterRecording(samples: samples)
            }
            Button("Discard", role: .destructive) {
                session?.discard()
                dismiss()
            }
            Button("Keep recording", role: .cancel) {}
        } message: {
            Text("\(session?.acceptedCount ?? 0) new samples.")
        }
    }

    private var title: String {
        switch target {
        case .newMap: "New recording"
        case .update: "Updating map"
        case .newVersion: "Recording new version"
        }
    }

    private func controls(_ session: RecordingSession) -> some View {
        let score = monitor.reading.flatMap { mode.score($0.metrics) }
        let accuracy = location.location?.horizontalAccuracy
        let gpsReady = accuracy.map { $0 >= 0 && $0 <= session.accuracyThreshold } ?? false

        return VStack(spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    if session.isPaused {
                        Image(systemName: "pause.fill").font(.caption).foregroundStyle(.yellow)
                        Text("PAUSED").font(.caption.weight(.bold)).foregroundStyle(.yellow)
                    } else {
                        PulsingDot(color: .red)
                        Text("REC").font(.caption.weight(.bold)).foregroundStyle(.red)
                    }
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        Text(Duration.seconds(context.date.timeIntervalSince(startedAt)),
                             format: .time(pattern: .minuteSecond))
                            .font(.subheadline.monospacedDigit().weight(.semibold))
                    }
                }
                Spacer()
                LegendBar().frame(width: 150)
            }

            HStack(spacing: 8) {
                stat("Samples", "\(session.acceptedCount)", icon: "mappin.circle.fill", color: Brand.teal)
                stat("Signal", Format.score(score), icon: "wifi", color: SignalColor.color(for: score))
                stat("GPS", Format.number(accuracy, unit: "m"), icon: "location.fill", color: gpsReady ? .green : .orange)
            }

            accessPointRow

            if !session.isPaused && !gpsReady {
                Label("Waiting for GPS accuracy of \(Format.number(session.accuracyThreshold, unit: "m")) or better. Stay outdoors or near windows.",
                      systemImage: "location.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Button {
                    session.togglePause()
                } label: {
                    Label(session.isPaused ? "Resume" : "Pause", systemImage: session.isPaused ? "play.fill" : "pause.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Button {
                    showFinish = true
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.red.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .foregroundStyle(.white)
        }
        .padding(18)
        .frame(maxWidth: 520)
        .background(Brand.navy.opacity(0.88), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        .environment(\.colorScheme, .dark)
        .padding()
    }

    private var accessPointRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.router.fill")
                .foregroundStyle(Brand.teal)
            Text(accessPointStatus)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(2)
            Spacer(minLength: 4)
            Button {
                showAccessPoints.toggle()
            } label: {
                Image(systemName: showAccessPoints ? "eye.fill" : "eye.slash.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .accessibilityLabel(showAccessPoints ? "Hide access points" : "Show access points")
        }
    }

    private var accessPointStatus: String {
        let located = accessPoints.count
        let current = monitor.reading?.bssid
            .flatMap(AccessPointLocator.nodeKey(for:))
            .flatMap { key in accessPoints.first { $0.id == key } }
        let count = located == 1 ? "1 access point located" : "\(located) access points located"
        if let current { return "On \(current.label) · \(count)" }
        if located == 0 { return "Locating access points. Walk around each node." }
        return count
    }

    private func stat(_ title: String, _ value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.caption).foregroundStyle(color)
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(.white)
            Text(title).font(.caption2).foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func begin() {
        guard session == nil else { return }
        let map: WiFiMap
        let isNewMap: Bool
        switch target {
        case .newMap:
            map = WiFiMap(name: WiFiMap.defaultName())
            context.insert(map)
            isNewMap = true
        case .update(let existing):
            map = existing
            isNewMap = false
        case .newVersion(let source):
            map = source.makeNewVersion(in: context)
            isNewMap = true
        }
        name = map.name
        startedAt = .now
        // Ad traffic would share the Wi-Fi link being measured.
        ads.isPausedForMeasurement = true

        let defaults = UserDefaults.standard
        let newSession = RecordingSession(
            map: map,
            isNewMap: isNewMap,
            context: context,
            accuracyThreshold: defaults.double(forKey: AppSettingsKey.accuracyThreshold, default: AppDefaults.accuracyThreshold),
            minSpacing: defaults.double(forKey: AppSettingsKey.minSampleSpacing, default: AppDefaults.minSampleSpacing)
        )
        session = newSession
        let location = location
        monitor.onReading = { reading in
            newSession.handle(reading, location: location.location)
        }
        location.setRecordingMode(true)
        location.requestPreciseIfNeeded()
        location.start()
        monitor.start()
    }

    private func end() {
        monitor.onReading = nil
        location.setRecordingMode(false)
        ads.isPausedForMeasurement = false
    }
}
