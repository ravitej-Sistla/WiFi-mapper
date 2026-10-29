import SwiftUI
import UIKit

/// Brand palette and shared styling. Colors adapt to light and dark mode.
enum Brand {
    static let navy = Color(red: 0.04, green: 0.09, blue: 0.22)
    static let indigo = Color(red: 0.11, green: 0.23, blue: 0.62)
    static let blue = Color(red: 0.16, green: 0.42, blue: 0.98)
    static let teal = Color(red: 0.0, green: 0.80, blue: 0.78)

    static let background = Color(light: UIColor(red: 0.95, green: 0.96, blue: 0.99, alpha: 1),
                                  dark: UIColor(red: 0.03, green: 0.05, blue: 0.11, alpha: 1))
    static let card = Color(light: .white,
                            dark: UIColor(red: 0.08, green: 0.11, blue: 0.19, alpha: 1))
    static let hairline = Color(light: UIColor(white: 0, alpha: 0.06),
                                dark: UIColor(white: 1, alpha: 0.08))

    static let heroGradient = LinearGradient(colors: [navy, indigo], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let actionGradient = LinearGradient(colors: [blue, teal], startPoint: .leading, endPoint: .trailing)
    static let signalGradient = Gradient(colors: [.red, .orange, .yellow, .green])
}

extension Color {
    init(light: UIColor, dark: UIColor) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Brand.hairline))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardModifier(padding: padding))
    }

    /// Branded background behind scrolling screens and forms.
    func brandBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(Brand.background.ignoresSafeArea())
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
}

/// Rounded-square icon like the ones in iOS Settings.
struct IconTile: View {
    let systemName: String
    var color: Color = Brand.blue
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Brand.actionGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Brand.blue.opacity(0.35), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Circular score ring, red → green, animated.
struct SignalRing: View {
    let score: Double?
    var lineWidth: CGFloat = 12
    var trackColor: Color = .secondary.opacity(0.15)
    var valueFont: Font = .system(size: 44, weight: .bold, design: .rounded)
    var caption: String? = nil

    var body: some View {
        ZStack {
            Circle().stroke(trackColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: (score ?? 0) / 100)
                .stroke(SignalColor.color(for: score).gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.8), value: score)
            VStack(spacing: 0) {
                Text(Format.score(score))
                    .font(valueFont)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.default, value: score)
                if let caption {
                    Text(caption)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Signal score \(Format.score(score)) out of 100")
    }
}

/// Weak → strong color key for heatmaps.
struct LegendBar: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("Weak").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
            Capsule()
                .fill(LinearGradient(gradient: Brand.signalGradient, startPoint: .leading, endPoint: .trailing))
                .frame(height: 6)
            Text("Strong").font(.caption2.weight(.medium)).foregroundStyle(.secondary)
        }
    }
}

/// Small pill label, e.g. a version badge.
struct Pill: View {
    let text: String
    var color: Color = Brand.blue

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
}

/// Pulsing dot for "live" and "recording" indicators.
struct PulsingDot: View {
    var color: Color = .green
    @State private var pulse = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .background(Circle().fill(color.opacity(0.4)).scaleEffect(pulse ? 2.4 : 1).opacity(pulse ? 0 : 1))
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
            }
    }
}
