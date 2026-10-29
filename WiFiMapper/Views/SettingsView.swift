import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettingsKey.scoringMode) private var mode = ScoringMode.fallback
    @AppStorage(AppSettingsKey.accuracyThreshold) private var accuracyThreshold = AppDefaults.accuracyThreshold
    @AppStorage(AppSettingsKey.minSampleSpacing) private var minSpacing = AppDefaults.minSampleSpacing
    @AppStorage(AppSettingsKey.gatewayOverride) private var gatewayOverride = ""
    @AppStorage(AppSettingsKey.throughputEnabled) private var throughputEnabled = false
    @AppStorage(AppSettingsKey.throughputURL) private var throughputURL = AppDefaults.throughputURL

    var body: some View {
        Form {
            Section {
                Picker("Default mode", selection: $mode) {
                    ForEach(ScoringMode.allCases) { Text($0.title).tag($0) }
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
                Stepper("GPS accuracy ≤ \(Format.number(accuracyThreshold, unit: "m"))",
                        value: $accuracyThreshold, in: 3...30, step: 1)
                Stepper("Sample every \(Format.number(minSpacing, unit: "m"))",
                        value: $minSpacing, in: 1...10, step: 1)
            } header: {
                Text("Recording")
            } footer: {
                Text("Readings taken while GPS accuracy is worse than the limit are skipped. Standing still re-samples the spot every \(Int(RecordingSession.stationaryResampleInterval)) s.")
            }

            Section {
                TextField(GatewayResolver.guessedGateway() ?? "e.g. 192.168.1.1", text: $gatewayOverride)
                    .keyboardType(.decimalPad)
                    .autocorrectionDisabled()
            } header: {
                Text("Router address")
            } footer: {
                Text("Leave blank to use the first address on your Wi-Fi network (shown above in grey). Set it if your router uses a different address.")
            }

            Section {
                Toggle("Measure throughput", isOn: $throughputEnabled)
                if throughputEnabled {
                    TextField("Download URL", text: $throughputURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("Throughput")
            } footer: {
                Text("Downloads a small file on every reading. This measures your internet connection as well as Wi-Fi and uses data, so it's off by default.")
            }
        }
        .navigationTitle("Settings")
    }
}
