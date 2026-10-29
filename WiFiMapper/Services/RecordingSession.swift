import CoreLocation
import Foundation
import Observation
import SwiftData

enum RecordingTarget: Hashable {
    case newMap
    case update(WiFiMap)
    case newVersion(of: WiFiMap)
}

/// Turns live readings plus GPS fixes into samples on a map.
@MainActor
@Observable
final class RecordingSession {
    /// Re-sample a spot you're standing still at after this long.
    static let stationaryResampleInterval: TimeInterval = 10
    /// Ignore GPS fixes older than this.
    static let maxLocationAge: TimeInterval = 5

    let map: WiFiMap
    let isNewMap: Bool
    let accuracyThreshold: Double
    let minSpacing: Double

    private(set) var acceptedCount = 0
    private(set) var rejectedForAccuracy = 0
    private(set) var isPaused = false

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var sessionSamples: [SignalSample] = []
    @ObservationIgnored private var lastLocation: CLLocation?
    @ObservationIgnored private var lastSampleDate: Date?
    @ObservationIgnored private let originalUpdatedAt: Date

    init(map: WiFiMap, isNewMap: Bool, context: ModelContext, accuracyThreshold: Double, minSpacing: Double) {
        self.map = map
        self.isNewMap = isNewMap
        self.context = context
        self.accuracyThreshold = accuracyThreshold
        self.minSpacing = minSpacing
        self.originalUpdatedAt = map.updatedAt
    }

    func handle(_ reading: SignalMonitor.Reading, location: CLLocation?) {
        guard !isPaused, let location else { return }
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= accuracyThreshold,
              abs(location.timestamp.timeIntervalSinceNow) <= Self.maxLocationAge else {
            rejectedForAccuracy += 1
            return
        }
        if let lastLocation, let lastSampleDate,
           location.distance(from: lastLocation) < minSpacing,
           reading.timestamp.timeIntervalSince(lastSampleDate) < Self.stationaryResampleInterval {
            return
        }

        let sample = SignalSample(
            timestamp: reading.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            ssid: reading.ssid,
            bssid: reading.bssid,
            metrics: reading.metrics
        )
        map.samples.append(sample)
        map.updatedAt = .now
        sessionSamples.append(sample)
        lastLocation = location
        lastSampleDate = reading.timestamp
        acceptedCount += 1
    }

    func togglePause() {
        isPaused.toggle()
    }

    func finish(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { map.name = trimmed }
        if acceptedCount > 0 { map.updatedAt = .now }
        try? context.save()
    }

    /// Throws away what this session recorded: the whole map if it was created for it.
    func discard() {
        if isNewMap {
            context.delete(map)
        } else {
            let added = Set(sessionSamples.map(\.persistentModelID))
            map.samples.removeAll { added.contains($0.persistentModelID) }
            for sample in sessionSamples { context.delete(sample) }
            map.updatedAt = originalUpdatedAt
        }
        sessionSamples.removeAll()
        try? context.save()
    }
}
