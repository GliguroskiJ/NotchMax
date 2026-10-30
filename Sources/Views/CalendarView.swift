import SwiftUI

struct CalendarView: View {
    @EnvironmentObject private var calendar: CalendarMonitor
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            switch calendar.access {
            case .granted:
                if calendar.events.isEmpty {
                    placeholder(symbol: "checkmark.circle", text: "Žádné události dnes ani zítra")
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(calendar.events) { event in
                                row(event)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            case .unknown:
                VStack(spacing: 10) {
                    placeholder(symbol: "calendar", text: "NotchMax potřebuje přístup ke kalendáři")
                    GlassPill(title: "Povolit přístup", symbol: "lock.open.fill") { calendar.requestAccess() }
                }
            case .denied:
                placeholder(symbol: "lock.fill", text: "Přístup zamítnut. Povol ho v Nastavení → Soukromí → Kalendáře.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholder(symbol: String, text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(Color.white.opacity(0.4))
            Text(text).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.55)).multilineTextAlignment(.center)
        }
    }

    private func row(_ e: CalEvent) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(e.color).frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(e.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.white).lineLimit(1)
                Text(subtitle(e)).font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
            }
            Spacer()
            if let url = e.joinURL {
                GlassPill(title: "Připojit", symbol: "video.fill", tint: Color.green.opacity(0.4)) { openURL(url) }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func subtitle(_ e: CalEvent) -> String {
        let cal = Calendar.current
        let day = cal.isDateInToday(e.start) ? "Dnes" : (cal.isDateInTomorrow(e.start) ? "Zítra" : e.start.formatted(date: .abbreviated, time: .omitted))
        if e.isAllDay { return "\(day) · celý den" }
        let from = e.start.formatted(date: .omitted, time: .shortened)
        let to = e.end.formatted(date: .omitted, time: .shortened)
        return "\(day) · \(from) – \(to)"
    }
}
