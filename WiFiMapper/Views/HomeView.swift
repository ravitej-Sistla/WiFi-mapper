import SwiftUI

struct HomeView: View {
    @Environment(LocationService.self) private var location
    @Environment(Router.self) private var router

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("WiFi Mapper", systemImage: "wifi")
                        .font(.headline)
                    Text("Record a walk around your property to build a Wi-Fi heatmap. Reopen a saved map to see the expected signal where you're standing.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if location.isDenied {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Location access is off", systemImage: "location.slash")
                            .font(.headline)
                        Text("WiFi Mapper needs precise location to place readings on the map. iOS also requires it to show the Wi-Fi network name.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
            }

            Section("Live signal") {
                LiveSignalCard()
            }

            Section {
                Button {
                    router.show(.record(.newMap))
                } label: {
                    Label("New Recording", systemImage: "record.circle")
                }
                Button {
                    router.show(.checkHere)
                } label: {
                    Label("Check Here", systemImage: "mappin.and.ellipse")
                }
            }

            HistorySection()
        }
        .navigationTitle("WiFi Mapper")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.show(.settings)
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
    }
}
