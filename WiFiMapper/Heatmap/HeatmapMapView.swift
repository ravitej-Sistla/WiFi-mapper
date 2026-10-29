import MapKit
import SwiftUI

/// Satellite map with the heatmap overlay and the live location dot.
struct HeatmapMapView: UIViewRepresentable {
    var points: [HeatPoint]
    var showSampleDots = false
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
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
