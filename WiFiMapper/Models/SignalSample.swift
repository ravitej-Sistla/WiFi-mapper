import Foundation
import SwiftData

@Model
final class SignalSample {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var ssid: String?
    /// The access point's MAC address — identifies which mesh node you were on.
    var bssid: String?
    var connected: Bool
    var appleStrength: Double?
    var rttMs: Double?
    var jitterMs: Double?
    var lossPct: Double?
    var throughputMbps: Double?
    var map: WiFiMap?

    init(
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        horizontalAccuracy: Double,
        ssid: String?,
        bssid: String?,
        metrics: SampleMetrics
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.ssid = ssid
        self.bssid = bssid
        self.connected = metrics.connected
        self.appleStrength = metrics.appleStrength
        self.rttMs = metrics.rttMs
        self.jitterMs = metrics.jitterMs
        self.lossPct = metrics.lossPct
        self.throughputMbps = metrics.throughputMbps
    }

    var metrics: SampleMetrics {
        SampleMetrics(
            connected: connected,
            appleStrength: appleStrength,
            rttMs: rttMs,
            jitterMs: jitterMs,
            lossPct: lossPct,
            throughputMbps: throughputMbps
        )
    }

    func copy() -> SignalSample {
        SignalSample(
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracy: horizontalAccuracy,
            ssid: ssid,
            bssid: bssid,
            metrics: metrics
        )
    }
}
