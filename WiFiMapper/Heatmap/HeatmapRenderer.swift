import MapKit

/// Paints the interpolated signal on a grid of roughly 1 m cells. Cells fade out
/// with distance from the nearest real sample so guesses don't look like data.
final class HeatmapRenderer: MKOverlayRenderer {
    static let cellMeters = 1.0
    static let minCellScreenPoints = 3.0
    static let maxAlpha = 0.6
    static let dotScreenRadius = 3.0

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let heatmap = overlay as? HeatmapOverlay else { return }
        let area = mapRect.intersection(heatmap.boundingMapRect)
        guard !area.isNull, !area.isEmpty else { return }

        let pointsPerMeter = MKMapPointsPerMeterAtLatitude(heatmap.coordinate.latitude)
        let cell = max(Self.cellMeters * pointsPerMeter, Self.minCellScreenPoints / Double(zoomScale))
        // Align the grid to the overlay so neighboring tiles line up.
        let origin = heatmap.boundingMapRect.origin
        let startX = origin.x + floor((area.minX - origin.x) / cell) * cell
        let startY = origin.y + floor((area.minY - origin.y) / cell) * cell
        let radius = heatmap.interpolator.radius

        var y = startY
        while y < area.maxY {
            var x = startX
            while x < area.maxX {
                let center = MKMapPoint(x: x + cell / 2, y: y + cell / 2).coordinate
                if let estimate = heatmap.interpolator.estimate(latitude: center.latitude, longitude: center.longitude) {
                    let fade = sqrt(max(0, 1 - estimate.nearestDistance / radius))
                    context.setFillColor(SignalColor.uiColor(for: estimate.value, alpha: Self.maxAlpha * fade).cgColor)
                    // Slight overlap hides hairline seams between cells.
                    context.fill(rect(for: MKMapRect(x: x, y: y, width: cell * 1.05, height: cell * 1.05)))
                }
                x += cell
            }
            y += cell
        }

        guard heatmap.showSampleDots else { return }
        let dotRadius = Self.dotScreenRadius / Double(zoomScale)
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(1 / zoomScale)
        for point in heatmap.points {
            let mapPoint = MKMapPoint(CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
            let dot = MKMapRect(x: mapPoint.x - dotRadius, y: mapPoint.y - dotRadius, width: 2 * dotRadius, height: 2 * dotRadius)
            guard dot.intersects(mapRect) else { continue }
            let r = rect(for: dot)
            context.setFillColor(SignalColor.uiColor(for: point.value).cgColor)
            context.fillEllipse(in: r)
            context.strokeEllipse(in: r)
        }
    }
}
