import SwiftUI

// MARK: - Sdílené stavební prvky panelu

/// Prázdný stav: ikona v kruhu + nadpis + volitelný popisek.
struct EmptyState: View {
    let symbol: String
    let title: String
    var message: String?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.7))
                .frame(width: 38, height: 38)
                .background(Circle().fill(Color.white.opacity(0.08)))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Malý popisek karty (ikona + název).
struct CardLabel: View {
    let symbol: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.white.opacity(0.55))
    }
}

/// Tenký ukazatel průběhu (kapsle).
struct ThinProgress: View {
    var value: Double
    var tint: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let clamped: Double = min(max(value, 0), 1)
            let fillWidth: CGFloat = max(height, geo.size.width * CGFloat(clamped))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(tint).frame(width: fillWidth)
            }
        }
        .frame(height: height)
        .animation(.smooth(duration: 0.4), value: value)
    }
}

/// Symbol baterie podle stavu nabití.
enum BatteryIcon {
    static func name(level: Int, charging: Bool) -> String {
        if charging { return "bolt.fill" }
        switch level {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}
