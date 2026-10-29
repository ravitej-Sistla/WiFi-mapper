import Foundation

/// UserDefaults keys, shared by `@AppStorage` in views and `ProbeSettings` in services.
enum AppSettingsKey {
    static let scoringMode = "scoringMode"
    static let accuracyThreshold = "accuracyThresholdMeters"
    static let minSampleSpacing = "minSampleSpacingMeters"
    static let gatewayOverride = "gatewayOverride"
    static let throughputEnabled = "throughputEnabled"
    static let throughputURL = "throughputURL"
}

enum AppDefaults {
    static let accuracyThreshold = 10.0
    static let minSampleSpacing = 2.0
    static let throughputURL = "https://speed.cloudflare.com/__down?bytes=250000"
}

struct ProbeSettings {
    var gatewayOverride: String?
    var throughputURL: URL?

    static func load(_ defaults: UserDefaults = .standard) -> ProbeSettings {
        let gateway = defaults.string(forKey: AppSettingsKey.gatewayOverride)?
            .trimmingCharacters(in: .whitespaces)
        let throughputOn = defaults.bool(forKey: AppSettingsKey.throughputEnabled)
        let urlString = defaults.string(forKey: AppSettingsKey.throughputURL) ?? AppDefaults.throughputURL
        return ProbeSettings(
            gatewayOverride: (gateway?.isEmpty ?? true) ? nil : gateway,
            throughputURL: throughputOn ? URL(string: urlString) : nil
        )
    }
}

extension UserDefaults {
    func double(forKey key: String, default fallback: Double) -> Double {
        object(forKey: key) as? Double ?? fallback
    }
}
