import SwiftUI

// MARK: - Pomocné rozšíření pro zobrazení událostí

extension CalEvent {
    /// Celodenní událost, nebo událost trvající (téměř) celý den, např. „Out of office“ 0:00–0:00.
    var isDayLong: Bool {
        isAllDay || end.timeIntervalSince(start) >= 23 * 3600
    }

    /// Skutečná schůzka: má čas začátku a nenulovou délku, netrvá celý den.
    var isMeeting: Bool {
        !isDayLong && end > start
    }

    var dayLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(start) { return "Dnes" }
        if cal.isDateInTomorrow(start) { return "Zítra" }
        return start.formatted(date: .abbreviated, time: .omitted)
    }

    var startText: String { start.formatted(date: .omitted, time: .shortened) }
    var endText: String { end.formatted(date: .omitted, time: .shortened) }

    /// Čas pro zobrazení: „Celý den“, „9:00 – 10:00“ nebo jen „9:00“ u událostí bez délky.
    var timeText: String {
        if isDayLong { return "Celý den" }
        if end <= start { return startText }
        return "\(startText) – \(endText)"
    }
}

extension CalendarMonitor {
    /// Nadcházející nebo probíhající schůzky (bez celodenních a „out of office“ událostí).
    var meetings: [CalEvent] {
        events.filter { $0.isMeeting && $0.end > now }
    }

    var nextMeeting: CalEvent? { meetings.first }

    /// Za kolik minut začíná nejbližší schůzka (nil, pokud žádná v budoucnu nezačíná).
    var minutesToNextMeeting: Int? {
        guard let e = meetings.first(where: { $0.start > now }) else { return nil }
        return Int(ceil(e.start.timeIntervalSince(now) / 60))
    }

    /// Nejbližší celodenní událost (pro doplňující informaci, když nejsou žádné schůzky).
    var firstDayLongEvent: CalEvent? {
        events.first { $0.isDayLong }
    }
}

// MARK: - Záložka Kalendář

struct CalendarView: View {
    @EnvironmentObject private var calendar: CalendarMonitor
    @Environment(\.openURL) private var openURL

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassCard(padding: 10)
    }

    @ViewBuilder
    private var content: some View {
        switch calendar.access {
        case .granted:
            if calendar.events.isEmpty {
                EmptyState(symbol: "checkmark.circle", title: "Volno", message: "Žádné události dnes ani zítra")
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
                EmptyState(symbol: "calendar", title: "Kalendář", message: "NotchMax potřebuje přístup ke kalendáři")
                GlassPill(title: "Povolit přístup", symbol: "lock.open.fill") { calendar.requestAccess() }
            }
        case .denied:
            EmptyState(symbol: "lock.fill", title: "Přístup zamítnut",
                       message: "Povol ho v Nastavení → Soukromí → Kalendáře.")
        }
    }

    private func row(_ e: CalEvent) -> some View {
        HStack(spacing: 10) {
            timeColumn(e)
                .frame(width: 46, alignment: .leading)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(e.color)
                .frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(subtitle(e))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let url = e.joinURL {
                GlassPill(title: "Připojit", symbol: "video.fill", tint: Color.green.opacity(0.4)) { openURL(url) }
            }
        }
        .padding(.horizontal, NotchLayout.spacingM)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NotchLayout.nestedRadius, style: .continuous)
                .fill(Color.white.opacity(e.isDayLong ? 0.04 : 0.07))
        )
    }

    @ViewBuilder
    private func timeColumn(_ e: CalEvent) -> some View {
        if e.isDayLong {
            Text("Celý den")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))
        } else {
            VStack(alignment: .leading, spacing: 1) {
                Text(e.startText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
                if e.end > e.start {
                    Text(e.endText)
                        .font(.system(size: 10, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }
        }
    }

    private func subtitle(_ e: CalEvent) -> String {
        var parts: [String] = [e.dayLabel]
        if let loc = e.location, !loc.isEmpty, !loc.lowercased().hasPrefix("http") {
            parts.append(loc)
        }
        return parts.joined(separator: " · ")
    }
}
