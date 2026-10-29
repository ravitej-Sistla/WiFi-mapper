import MapKit
import SwiftUI

/// Satellite map with the heatmap overlay, estimated access points and the live location dot.
struct HeatmapMapView: UIViewRepresentable {
    var points: [HeatPoint]
    var showSampleDots = false
    var accessPoints: [AccessPointEstimate] = []
    /// Keep the map centered on the user (recording). Otherwise zoom to the map's samples once.
    var followsUser = false

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .flat)
        mapView.pointOfInterestFilter = .excludingAll
        mapView.showsUserLocation = true
        mapView.showsScale = true
        // Following starts once the first fix arrives, after zooming in (see the coordinator).
        context.coordinator.zoomToUser = followsUser || points.isEmpty

        let trackingButton = MKUserTrackingButton(mapView: mapView)
        trackingButton.translatesAutoresizingMaskIntoConstraints = false
        trackingButton.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.85)
        trackingButton.layer.cornerRadius = 8
        mapView.addSubview(trackingButton)
        NSLayoutConstraint.activate([
            trackingButton.topAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.topAnchor, constant: 12),
            trackingButton.leadingAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.leadingAnchor, constant: 12),
        ])
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.sync(accessPoints, on: mapView)
        guard points != coordinator.points || showSampleDots != coordinator.showSampleDots else { return }
        coordinator.points = points
        coordinator.showSampleDots = showSampleDots

        if let old = coordinator.overlay { mapView.removeOverlay(old) }
        coordinator.overlay = HeatmapOverlay(points: points, showSampleDots: showSampleDots)
        guard let overlay = coordinator.overlay else { return }
        mapView.addOverlay(overlay, level: .aboveRoads)

        if !followsUser && !coordinator.didFit {
            coordinator.didFit = true
            // Wait a runloop so the map has its final size before fitting.
            DispatchQueue.main.async {
                mapView.setVisibleMapRect(overlay.boundingMapRect,
                                          edgePadding: UIEdgeInsets(top: 60, left: 30, bottom: 60, right: 30),
                                          animated: false)
            }
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var points: [HeatPoint] = []
        var showSampleDots = false
        var overlay: HeatmapOverlay?
        var didFit = false
        /// Zoom to property scale on the first location fix (recording, or a map with no samples).
        var zoomToUser = false
        static let userCameraDistance = 300.0

        private var pendingZoom = false

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard zoomToUser, userLocation.location != nil else { return }
            zoomToUser = false
            // Follow mode picks its own (city-scale) zoom and ignores region changes while it settles,
            // so cap the zoom-out distance until it has settled, then lift the cap.
            pendingZoom = true
            mapView.setCameraZoomRange(MKMapView.CameraZoomRange(maxCenterCoordinateDistance: Self.userCameraDistance), animated: false)
            mapView.setUserTrackingMode(.follow, animated: false)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard pendingZoom else { return }
            pendingZoom = false
            DispatchQueue.main.async {
                mapView.setCameraZoomRange(MKMapView.CameraZoomRange(minCenterCoordinateDistance: 0), animated: false)
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let heatmap = overlay as? HeatmapOverlay {
                return HeatmapRenderer(overlay: heatmap)
            }
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.fillColor = UIColor.white.withAlphaComponent(0.12)
                renderer.strokeColor = UIColor.white.withAlphaComponent(0.9)
                renderer.lineWidth = 1.5
                renderer.lineDashPattern = [5, 4]
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        // MARK: Access points

        private var accessPoints: [AccessPointEstimate] = []
        private var annotations: [String: AccessPointAnnotation] = [:]
        private var circles: [MKCircle] = []

        /// Adds, moves and removes access point pins; uncertainty circles are redrawn.
        func sync(_ estimates: [AccessPointEstimate], on mapView: MKMapView) {
            guard estimates != accessPoints else { return }
            accessPoints = estimates

            let ids = Set(estimates.map(\.id))
            for (id, annotation) in annotations where !ids.contains(id) {
                mapView.removeAnnotation(annotation)
                annotations[id] = nil
            }
            for estimate in estimates {
                if let annotation = annotations[estimate.id] {
                    UIView.animate(withDuration: 0.4) { annotation.update(estimate) }
                    (mapView.view(for: annotation) as? MKMarkerAnnotationView)?.markerTintColor = annotation.tint
                } else {
                    let annotation = AccessPointAnnotation(estimate)
                    annotations[estimate.id] = annotation
                    mapView.addAnnotation(annotation)
                }
            }

            mapView.removeOverlays(circles)
            circles = estimates.map {
                MKCircle(center: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude),
                         radius: $0.radiusMeters)
            }
            mapView.addOverlays(circles, level: .aboveLabels)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? AccessPointAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: AccessPointAnnotation.reuseID) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: AccessPointAnnotation.reuseID)
            view.annotation = annotation
            view.glyphImage = UIImage(systemName: "wifi.router.fill")
            view.markerTintColor = annotation.tint
            view.titleVisibility = .visible
            view.subtitleVisibility = .hidden
            view.displayPriority = .required
            view.canShowCallout = true
            return view
        }
    }
}

final class AccessPointAnnotation: NSObject, MKAnnotation {
    static let reuseID = "accessPoint"

    @objc dynamic var coordinate: CLLocationCoordinate2D
    private(set) var title: String?
    private(set) var subtitle: String?
    private(set) var confidence: AccessPointEstimate.Confidence

    init(_ estimate: AccessPointEstimate) {
        coordinate = CLLocationCoordinate2D(latitude: estimate.latitude, longitude: estimate.longitude)
        confidence = estimate.confidence
        super.init()
        update(estimate)
    }

    func update(_ estimate: AccessPointEstimate) {
        coordinate = CLLocationCoordinate2D(latitude: estimate.latitude, longitude: estimate.longitude)
        confidence = estimate.confidence
        title = estimate.label
        subtitle = "±\(Int(estimate.radiusMeters.rounded())) m · \(estimate.confidence.label) confidence · \(estimate.sampleCount) samples"
    }

    var tint: UIColor {
        switch confidence {
        case .high: UIColor(Brand.indigo)
        case .medium: UIColor(Brand.blue)
        case .low: .systemGray
        }
    }
}
