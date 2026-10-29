import SwiftData
import SwiftUI

/// Builds the heatmap live as you walk. Stop asks to save or discard.
struct RecordingView: View {
    let target: RecordingTarget

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(SignalMonitor.self) private var monitor
    @Environment(LocationService.self) private var location
    @AppStorage(AppSettingsKey.scoringMode) private var mode = ScoringMode.fallback
    @State private var session: RecordingSession?
    @State private var showFinish = false
    @State private var name = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            HeatmapMapView(points: session?.map.heatPoints(mode: mode) ?? [], showSampleDots: true, followsUser: true)
                .ignoresSafeArea(edges: .bottom)
            if let session {
                controls(session)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .onAppear(perform: begin)
        .onDisappear(perform: end)
        .alert("Save recording", isPresented: $showFinish) {
            TextField("Name", text: $name)
            Button("Save") {
                session?.finish(name: name)
                dismiss()
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

        return VStack(spacing: 12) {
            HStack {
                stat("Samples", "\(session.acceptedCount)")
                stat("Signal now", Format.score(score), color: SignalColor.color(for: score))
                stat("GPS", Format.number(accuracy, unit: "m"), color: gpsReady ? .primary : .orange)
            }
            if session.isPaused {
                Label("Paused", systemImage: "pause.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !gpsReady {
                Label("Waiting for GPS accuracy of \(Format.number(session.accuracyThreshold, unit: "m")) or better. Stay outdoors or near windows.",
                      systemImage: "location.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            HStack {
                Button(session.isPaused ? "Resume" : "Pause") {
                    session.togglePause()
                }
                .buttonStyle(.bordered)
                Button("Stop") {
                    showFinish = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding()
        .frame(maxWidth: 500)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding()
    }

    private func stat(_ title: String, _ value: String, color: Color = .primary) -> some View {
        VStack {
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
    }
}
