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
        if followsUser || points.isEmpty {
            mapView.setUserTrackingMode(.follow, animated: false)
        }

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

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let heatmap = overlay as? HeatmapOverlay {
                return HeatmapRenderer(overlay: heatmap)
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
