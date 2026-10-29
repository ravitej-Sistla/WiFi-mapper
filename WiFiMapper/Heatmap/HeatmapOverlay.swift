import MapKit

final class HeatmapOverlay: NSObject, MKOverlay {
    let points: [HeatPoint]
    let interpolator: IDWInterpolator
    let showSampleDots: Bool
    let boundingMapRect: MKMapRect
    let coordinate: CLLocationCoordinate2D

    init?(points: [HeatPoint], radius: Double = IDWInterpolator.defaultRadius, showSampleDots: Bool) {
        guard !points.isEmpty else { return nil }
        self.points = points
        self.interpolator = IDWInterpolator(points: points, radius: radius)
        self.showSampleDots = showSampleDots

        let mapPoints = points.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }
        let minX = mapPoints.map(\.x).min()!, maxX = mapPoints.map(\.x).max()!
        let minY = mapPoints.map(\.y).min()!, maxY = mapPoints.map(\.y).max()!
        let centerLatitude = MKMapPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2).coordinate.latitude
        let padding = radius * MKMapPointsPerMeterAtLatitude(centerLatitude)
        boundingMapRect = MKMapRect(x: minX - padding, y: minY - padding,
                                    width: maxX - minX + 2 * padding, height: maxY - minY + 2 * padding)
        coordinate = MKMapPoint(x: boundingMapRect.midX, y: boundingMapRect.midY).coordinate
        super.init()
    }
}
