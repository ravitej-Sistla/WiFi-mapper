import SwiftUI

struct HomeView: View {
    @Environment(LocationService.self) private var location
    @Environment(Router.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                LiveSignalCard()

                if location.isDenied {
                    locationBanner
                }

                VStack(spacing: 12) {
                    Button {
                        router.show(.record(.newMap))
                    } label: {
                        Label("Start New Recording", systemImage: "record.circle.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())

                    Button {
                        router.show(.checkHere)
                    } label: {
                        HStack(spacing: 14) {
                            IconTile(systemName: "mappin.and.ellipse", color: Brand.teal, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Check Here").font(.headline)
                                Text("Compare this spot with your saved maps")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .card(padding: 14)
                    }
                    .buttonStyle(.plain)
                }

                HistorySection()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .brandBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Brand.heroGradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text("WiFi Mapper").font(.title2.bold())
                Text("Coverage heatmaps for your property")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                router.show(.settings)
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(Brand.card, in: Circle())
                    .overlay(Circle().strokeBorder(Brand.hairline))
            }
            .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
    }

    private var locationBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(systemName: "location.slash.fill", color: .orange, size: 34)
            VStack(alignment: .leading, spacing: 6) {
                Text("Location access is off").font(.headline)
                Text("Precise location places readings on the map. iOS also requires it to show the Wi-Fi network name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.caption.weight(.semibold))
            }
        }
        .card(padding: 14)
    }
}
