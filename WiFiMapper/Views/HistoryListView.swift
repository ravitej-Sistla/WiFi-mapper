import SwiftData
import SwiftUI

/// Saved maps, most recently updated first. Swipe to delete or rename.
struct HistorySection: View {
    @Query(sort: \WiFiMap.updatedAt, order: .reverse) private var maps: [WiFiMap]
    @Environment(\.modelContext) private var context
    @AppStorage(AppSettingsKey.scoringMode) private var mode = ScoringMode.fallback
    @State private var renaming: WiFiMap?
    @State private var newName = ""

    var body: some View {
        Section("Saved maps") {
            if maps.isEmpty {
                Text("No maps yet. Tap New Recording and walk around your property.")
                    .foregroundStyle(.secondary)
            }
            ForEach(maps) { map in
                NavigationLink(value: Route.map(map)) {
                    MapRow(map: map, mode: mode)
                }
                .swipeActions {
                    Button("Delete", role: .destructive) {
                        context.delete(map)
                        try? context.save()
                    }
                    Button("Rename") {
                        newName = map.name
                        renaming = map
                    }
                    .tint(.blue)
                }
            }
        }
        .renameAlert(map: $renaming, name: $newName)
    }
}

struct MapRow: View {
    let map: WiFiMap
    let mode: ScoringMode

    var body: some View {
        let average = map.averageScore(mode: mode)
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(map.name).font(.headline).lineLimit(1)
                    Text("v\(map.version)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: Capsule())
                }
                Text("Updated \(map.updatedAt.formatted(.relative(presentation: .named))) · \(map.samples.count) samples")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Format.score(average))
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(SignalColor.color(for: average))
                .accessibilityLabel("Average score \(Format.score(average))")
        }
    }
}

extension View {
    /// Alert with a text field that renames `map` when it's set.
    func renameAlert(map: Binding<WiFiMap?>, name: Binding<String>) -> some View {
        alert("Rename map", isPresented: Binding(
            get: { map.wrappedValue != nil },
            set: { if !$0 { map.wrappedValue = nil } }
        )) {
            TextField("Name", text: name)
            Button("Save") {
                let trimmed = name.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if let target = map.wrappedValue, !trimmed.isEmpty {
                    target.name = trimmed
                    try? target.modelContext?.save()
                }
                map.wrappedValue = nil
            }
            Button("Cancel", role: .cancel) { map.wrappedValue = nil }
        }
    }
}
