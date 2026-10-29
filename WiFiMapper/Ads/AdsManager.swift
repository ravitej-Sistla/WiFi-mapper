import AppTrackingTransparency
import GoogleMobileAds
import Observation
import UIKit
import UserMessagingPlatform

/// Consent, loading and display of ads. Ad traffic shares the Wi-Fi link the app is
/// measuring, so nothing loads while `isPausedForMeasurement` is set (during a recording).
@MainActor
@Observable
final class AdsManager: NSObject {
    private(set) var nativeAd: NativeAd?
    private(set) var isStarted = false
    /// GDPR regions require a way to change consent later (shown in Settings).
    private(set) var privacyOptionsRequired = false

    var adsRemoved = false {
        didSet {
            guard adsRemoved else { return }
            nativeAd = nil
            interstitial = nil
        }
    }

    var isPausedForMeasurement = false {
        didSet {
            if !isPausedForMeasurement { loadAdsIfNeeded() }
        }
    }

    var showsAds: Bool { isStarted && !adsRemoved && AdConfig.isConfigured }

    @ObservationIgnored private var isStarting = false
    @ObservationIgnored private var adLoader: AdLoader?
    @ObservationIgnored private var nativeLoadedAt: Date?
    @ObservationIgnored private var interstitial: InterstitialAd?
    @ObservationIgnored private var interstitialLoadedAt: Date?
    @ObservationIgnored private var isLoadingInterstitial = false
    @ObservationIgnored private var lastInterstitialAt: Date?

    /// Gathers consent (UMP, then App Tracking Transparency) and starts the SDK.
    /// Call once location permission has been answered, so prompts don't stack at first launch.
    func startIfNeeded() async {
        guard AdConfig.isConfigured, !adsRemoved, !isStarted, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        if !Self.skipsConsent {
            let consent = ConsentInformation.shared
            try? await consent.requestConsentInfoUpdate(with: RequestParameters())
            try? await ConsentForm.loadAndPresentIfRequired(from: nil)
            privacyOptionsRequired = consent.privacyOptionsRequirementStatus == .required
            guard consent.canRequestAds else { return }

            if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
                _ = await ATTrackingManager.requestTrackingAuthorization()
            }
        }
        _ = await MobileAds.shared.start()
        isStarted = true
        loadAdsIfNeeded()
    }

    func loadAdsIfNeeded() {
        guard showsAds, !isPausedForMeasurement else { return }
        loadNativeIfNeeded()
        loadInterstitialIfNeeded()
    }

    /// Shows a full-screen ad after a saved recording, at most once per `interstitialMinInterval`.
    func showInterstitialAfterRecording(samples: Int) {
        guard showsAds, samples >= AdConfig.interstitialMinSamples else { return }
        if let lastInterstitialAt, Date.now.timeIntervalSince(lastInterstitialAt) < AdConfig.interstitialMinInterval { return }
        guard let ad = interstitial, let loadedAt = interstitialLoadedAt,
              Date.now.timeIntervalSince(loadedAt) < AdConfig.adLifetime else {
            interstitial = nil
            loadInterstitialIfNeeded()
            return
        }

        Task {
            try? await Task.sleep(for: AdConfig.interstitialDelay)
            // A new recording may have started in the meantime.
            guard !isPausedForMeasurement, let root = Self.topViewController() else { return }
            interstitial = nil
            lastInterstitialAt = .now
            ad.fullScreenContentDelegate = self
            ad.present(from: root)
        }
    }

    func presentPrivacyOptions() async {
        try? await ConsentForm.presentPrivacyOptionsForm(from: Self.topViewController())
    }

    private func loadNativeIfNeeded() {
        guard let unitID = AdConfig.nativeUnitID, adLoader?.isLoading != true else { return }
        if nativeAd != nil, let nativeLoadedAt, Date.now.timeIntervalSince(nativeLoadedAt) < AdConfig.adLifetime { return }

        let video = VideoOptions()
        video.shouldStartMuted = true
        let loader = AdLoader(adUnitID: unitID, rootViewController: nil, adTypes: [.native], options: [video])
        loader.delegate = self
        adLoader = loader
        loader.load(Request())
    }

    private func loadInterstitialIfNeeded() {
        guard let unitID = AdConfig.interstitialUnitID, interstitial == nil, !isLoadingInterstitial else { return }
        isLoadingInterstitial = true
        Task {
            defer { isLoadingInterstitial = false }
            guard let ad = try? await InterstitialAd.load(with: unitID, request: Request()),
                  showsAds else { return }
            interstitial = ad
            interstitialLoadedAt = .now
        }
    }

    /// Debug builds only: `-skipAdConsent` skips the consent prompts so screens can be
    /// checked in the simulator. Test ads are non-personalized either way.
    private static var skipsConsent: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-skipAdConsent")
        #else
        false
        #endif
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

extension AdsManager: NativeAdLoaderDelegate {
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        guard showsAds else { return }
        self.nativeAd = nativeAd
        nativeLoadedAt = .now
    }

    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        // No fill or offline: Home simply shows no ad card.
    }
}

extension AdsManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        loadAdsIfNeeded()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        loadAdsIfNeeded()
    }
}
