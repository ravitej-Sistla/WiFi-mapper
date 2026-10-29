import Foundation

enum Format {
    static func score(_ value: Double?) -> String {
        value.map { String(Int($0.rounded())) } ?? "—"
    }

    static func number(_ value: Double?, digits: Int = 0, unit: String = "") -> String {
        guard let value else { return "—" }
        let text = value.formatted(.number.precision(.fractionLength(digits)))
        return unit.isEmpty ? text : "\(text) \(unit)"
    }

    static func correlation(_ value: Double?) -> String {
        value.map { $0.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())) } ?? "—"
    }

    static func percent(_ fraction: Double?) -> String {
        fraction.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "—"
    }
}
