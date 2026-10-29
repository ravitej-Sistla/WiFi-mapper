import Foundation
import SwiftData

@Model
final class WiFiMap {
    @Attribute(.unique) var mapID: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date
    var version: Int
    /// Shared by every version of the same property map.
    var lineageID: UUID
    /// The map this version was copied from, if any.
    var parentMapID: UUID?
    @Relationship(deleteRule: .cascade, inverse: \SignalSample.map)
    var samples: [SignalSample] = []

    init(name: String, version: Int = 1, lineageID: UUID = UUID(), parentMapID: UUID? = nil) {
        self.mapID = UUID()
        self.name = name
        self.createdAt = .now
        self.updatedAt = .now
        self.version = version
        self.lineageID = lineageID
        self.parentMapID = parentMapID
    }

    static func defaultName(date: Date = .now) -> String {
        "Property map – \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

extension WiFiMap {
    func heatPoints(mode: ScoringMode) -> [HeatPoint] {
        samples.compactMap { sample in
            mode.score(sample.metrics).map {
                HeatPoint(latitude: sample.latitude, longitude: sample.longitude, value: $0)
            }
        }
    }

    func averageScore(mode: ScoringMode) -> Double? {
        Stats.mean(samples.compactMap { mode.score($0.metrics) })
    }

    /// Copies this map's samples into a new version in the same lineage.
    func makeNewVersion(in context: ModelContext) -> WiFiMap {
        let lineage = lineageID
        let descriptor = FetchDescriptor<WiFiMap>(predicate: #Predicate { $0.lineageID == lineage })
        let latestVersion = ((try? context.fetch(descriptor)) ?? []).map(\.version).max() ?? version

        let copy = WiFiMap(name: name, version: latestVersion + 1, lineageID: lineageID, parentMapID: mapID)
        context.insert(copy)
        for sample in samples {
            copy.samples.append(sample.copy())
        }
        return copy
    }
}
