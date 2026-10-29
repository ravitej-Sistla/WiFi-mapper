import SwiftUI
import UIKit

/// Red (0) → yellow (50) → green (100).
enum SignalColor {
    static func hue(for score: Double) -> CGFloat {
        CGFloat(SignalScoring.clamp(score) / 100 * 0.33)
    }

    static func uiColor(for score: Double, alpha: CGFloat = 1) -> UIColor {
        UIColor(hue: hue(for: score), saturation: 0.9, brightness: 0.95, alpha: alpha)
    }

    static func color(for score: Double?) -> Color {
        guard let score else { return .secondary }
        return Color(uiColor: uiColor(for: score))
    }
}
