import CoreLocation
import Observation

@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var location: CLLocation?
    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy

    private let manager = CLLocationManager()

    override init() {
        super.init()
        authorization = manager.authorizationStatus
        accuracyAuthorization = manager.accuracyAuthorization
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
    }

    var isAuthorized: Bool {
        authorization == .authorizedWhenInUse || authorization == .authorizedAlways
    }

    var isDenied: Bool {
        authorization == .denied || authorization == .restricted
    }

    func requestAccess() {
        if authorization == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if isAuthorized {
            start()
        }
    }

    func start() {
        guard isAuthorized else { return }
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    /// Asks for one-off precise location if the user granted only approximate location.
    func requestPreciseIfNeeded() {
        guard isAuthorized, manager.accuracyAuthorization == .reducedAccuracy else { return }
        manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "WiFiMapping")
    }

    /// Keeps location (and therefore the app) running with the screen locked while recording.
    func setRecordingMode(_ recording: Bool) {
        manager.allowsBackgroundLocationUpdates = recording
        manager.showsBackgroundLocationIndicator = recording
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in self.location = latest }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        let accuracy = manager.accuracyAuthorization
        Task { @MainActor in
            self.authorization = status
            self.accuracyAuthorization = accuracy
            self.start()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Transient failures (e.g. no fix yet indoors) are expected; keep the last good location.
    }
}
