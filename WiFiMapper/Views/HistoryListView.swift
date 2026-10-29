import SwiftData
import SwiftUI

/// Saved maps, most recently updated first. Long-press a card to rename or delete.
struct HistorySection: View {
    @Query(sort: \WiFiMap.updatedAt, order: .reverse) private var maps: [WiFiMap]
    @Environment(\.modelContext) private var context
    @AppStorage(AppSettingsKey.scoringMode) private var mode = ScoringMode.fallback
    @State private var renaming: WiFiMap?
    @State private var newName = ""
    @State private var deleting: WiFiMap?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Saved maps", trailing: maps.isEmpty ? nil : "\(maps.count)")

            if maps.isEmpty {
                emptyState
            }
            ForEach(maps) { map in
                NavigationLink(value: Route.map(map)) {
                    MapRow(map: map, mode: mode)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        newName = map.name
                        renaming = map
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        deleting = map
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .renameAlert(map: $renaming, name: $newName)
        .confirmationDialog("Delete this map?", isPresented: Binding(
            get: { deleting != nil },
            set: { if !$0 { deleting = nil } }
        ), titleVisibility: .visible) {
            Button("Delete map", role: .destructive) {
                if let deleting {
                    context.delete(deleting)
                    try? context.save()
                }
                deleting = nil
            }
        } message: {
            Text("Its samples will be removed from this device. Other versions are kept.")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "map")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Brand.blue.gradient)
            Text("No maps yet").font(.headline)
            Text("Tap Start New Recording and walk around your property to build your first coverage map.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .card()
    }
}

struct MapRow: View {
    let map: WiFiMap
    let mode: ScoringMode

    var body: some View {
        let average = map.averageScore(mode: mode)
        HStack(spacing: 14) {
            SignalRing(score: average, lineWidth: 5, valueFont: .system(size: 15, weight: .bold, design: .rounded))
                .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(map.name).font(.headline).lineLimit(1)
                    Pill(text: "v\(map.version)")
                }
                HStack(spacing: 10) {
                    Label(map.updatedAt.formatted(.relative(presentation: .named)), systemImage: "clock")
                    Text("\(map.samples.count) samples")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .labelStyle(CompactLabelStyle())
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Average score \(Format.score(average))")
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
            configuration.title
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
