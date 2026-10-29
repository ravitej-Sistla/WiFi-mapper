import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettingsKey.scoringMode) private var mode = ScoringMode.fallback
    @AppStorage(AppSettingsKey.accuracyThreshold) private var accuracyThreshold = AppDefaults.accuracyThreshold
    @AppStorage(AppSettingsKey.minSampleSpacing) private var minSpacing = AppDefaults.minSampleSpacing
    @AppStorage(AppSettingsKey.gatewayOverride) private var gatewayOverride = ""
    @AppStorage(AppSettingsKey.throughputEnabled) private var throughputEnabled = false
    @AppStorage(AppSettingsKey.throughputURL) private var throughputURL = AppDefaults.throughputURL
    @Environment(PurchaseStore.self) private var store
    @Environment(AdsManager.self) private var ads

    var body: some View {
        Form {
            Section {
                Picker(selection: $mode) {
                    ForEach(ScoringMode.allCases) { Text($0.title).tag($0) }
                } label: {
                    row("Default mode", icon: "gauge.with.dots.needle.67percent", color: Brand.blue)
                }
                Text(mode.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Scoring")
            } footer: {
                Text("Recordings keep the raw measurements, so changing this re-scores every saved map.")
            }

            Section {
                Stepper(value: $accuracyThreshold, in: 3...30, step: 1) {
                    row("GPS accuracy ≤ \(Format.number(accuracyThreshold, unit: "m"))", icon: "location.fill", color: .green)
                }
                Stepper(value: $minSpacing, in: 1...10, step: 1) {
                    row("Sample every \(Format.number(minSpacing, unit: "m"))", icon: "ruler.fill", color: .orange)
                }
            } header: {
                Text("Recording")
            } footer: {
                Text("Readings taken while GPS accuracy is worse than the limit are skipped. Standing still re-samples the spot every \(Int(RecordingSession.stationaryResampleInterval)) s.")
            }

            Section {
                HStack(spacing: 12) {
                    IconTile(systemName: "wifi.router.fill", color: .indigo)
                    TextField(GatewayResolver.guessedGateway() ?? "e.g. 192.168.1.1", text: $gatewayOverride)
                        .keyboardType(.decimalPad)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("Router address")
            } footer: {
                Text("Leave blank to use the first address on your Wi-Fi network (shown in grey). Set it if your router uses a different address.")
            }

            Section {
                Toggle(isOn: $throughputEnabled) {
                    row("Measure throughput", icon: "arrow.down.circle.fill", color: Brand.teal)
                }
                if throughputEnabled {
                    TextField("Download URL", text: $throughputURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.footnote.monospaced())
                }
            } header: {
                Text("Throughput")
            } footer: {
                Text("Downloads a small file on every reading. This measures your internet connection as well as Wi-Fi and uses data, so it's off by default.")
            }

            Section {
                if store.adsRemoved {
                    row("Ads removed — thank you!", icon: "checkmark.seal.fill", color: .green)
                } else {
                    Button {
                        Task { await store.purchaseRemoveAds() }
                    } label: {
                        HStack {
                            row("Remove ads", icon: "sparkles", color: .pink)
                            Spacer()
                            if store.isPurchasing {
                                ProgressView()
                            } else if let product = store.removeAdsProduct {
                                Text(product.displayPrice)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 5)
                                    .background(Brand.blue.opacity(0.14), in: Capsule())
                            } else {
                                Text("Unavailable").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    .disabled(store.removeAdsProduct == nil || store.isPurchasing)
                }
                Button("Restore purchases") {
                    Task { await store.restore() }
                }
                if ads.privacyOptionsRequired {
                    Button("Ad privacy choices") {
                        Task { await ads.presentPrivacyOptions() }
                    }
                }
            } header: {
                Text("Ads")
            } footer: {
                Text("A one-time purchase removes all ads. Ads never load while a recording is measuring.")
            }

            Section {
                VStack(spacing: 8) {
                    Image(systemName: "wifi")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(Brand.heroGradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    Text("WiFi Mapper").font(.headline)
                    Text("Version \(appVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Your maps stay on this device. No account needed. Ads are provided by Google AdMob.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .brandBackground()
        .navigationTitle("Settings")
        .alert("Purchase failed", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private func row(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            IconTile(systemName: icon, color: color)
            Text(title)
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
