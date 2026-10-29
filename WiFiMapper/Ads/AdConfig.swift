import Foundation

enum AdConfig {
    #if DEBUG
    // Google's test ad units. Google requires test ads during development: tapping
    // real ads from your own devices can get the AdMob account suspended.
    static let nativeUnitID: String? = "ca-app-pub-3940256099942544/3986624511"
    static let interstitialUnitID: String? = "ca-app-pub-3940256099942544/4411468910"
    #else
    // Before releasing: your AdMob ad unit IDs. Release builds show no ads until these are set.
    // Also replace GADApplicationIdentifier in project.yml with your AdMob app ID.
    static let nativeUnitID: String? = nil
    static let interstitialUnitID: String? = nil
    #endif

    static var isConfigured: Bool { nativeUnitID != nil || interstitialUnitID != nil }

    /// At most one full-screen ad per this interval.
    static let interstitialMinInterval: TimeInterval = 5 * 60
    /// Recordings shorter than this don't trigger a full-screen ad.
    static let interstitialMinSamples = 10
    /// Loaded ads expire after an hour; reload a little before that.
    static let adLifetime: TimeInterval = 55 * 60
    /// Give the navigation pop back to Home time to finish before presenting.
    static let interstitialDelay: Duration = .milliseconds(700)

    static let removeAdsProductID = "com.ravitej.wifimapper.removeads"
}
