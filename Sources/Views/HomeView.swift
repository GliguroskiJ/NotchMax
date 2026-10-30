import SwiftUI

/// Přehled: přehrávač + nejbližší schůzka + baterie.
struct HomeView: View {
    var body: some View {
        HStack(spacing: NotchLayout.spacingM) {
            MediaCard()
            VStack(spacing: NotchLayout.spacingM) {
                NextEventCard()
                BatteryCard()
            }
            .frame(width: NotchLayout.columnWidth)
        }
    }
}

// MARK: - Přehrávač

struct MediaCard: View {
    @EnvironmentObject private var media: MediaMonitor
    @EnvironmentObject private var settings: AppSettings

    private let artSize: CGFloat = 152

    var body: some View {
        Group {
            if media.hasTrack {
                player
            } else {
                EmptyState(symbol: "music.note", title: "Nic nehraje", message: "Spusť Apple Music nebo Spotify")
            }
        }
        .glassCard(padding: 10)
        .animation(.smooth(duration: 0.3), value: media.hasTrack)
    }

    private var player: some View {
        HStack(alignment: .center, spacing: NotchLayout.spacingL) {
            artwork
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "music.note")
                        .font(.system(size: 9, weight: .bold))
                    Text(media.source?.appName ?? "")
                        .font(.system(size: 10, weight: .semibold))
                    Spacer(minLength: 4)
                    EqualizerBars(color: settings.accent.color, active: media.isPlaying)
                }
                .foregroundStyle(Color.white.opacity(0.45))

                Text(media.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .padding(.top, 6)
                Text(media.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
                    .padding(.top, 2)

                Spacer(minLength: 6)
                controls
            }
            .padding(.vertical, 4)
            .padding(.trailing, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    private var artwork: some View {
        ZStack {
            if let art = media.artwork {
                Image(nsImage: art)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.05)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        }
        .frame(width: artSize, height: artSize)
        .clipShape(RoundedRectangle(cornerRadius: NotchLayout.nestedRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.4), radius: 8, x: 0, y: 4)
    }

    /// Všechna tlačítka přehrávání v jedné skleněné kapsli, play zvýrazněné.
    private var controls: some View {
        GlassContainer(spacing: 6) {
            HStack(spacing: 6) {
                TransportButton(symbol: "backward.fill", size: 30) { media.previous() }
                TransportButton(symbol: media.isPlaying ? "pause.fill" : "play.fill", size: 38, prominent: true) {
                    media.togglePlayPause()
                }
                TransportButton(symbol: "forward.fill", size: 30) { media.next() }
            }
            .padding(4)
            .notchGlass(in: Capsule(), tint: Color.white.opacity(0.05))
        }
    }
}

private struct TransportButton: View {
    let symbol: String
    let size: CGFloat
    var prominent = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(prominent ? Color.black : Color.white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .background(Circle().fill(backgroundColor))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(hovering ? 1.08 : 1)
        .animation(.smooth(duration: 0.16), value: hovering)
        .animation(.smooth(duration: 0.2), value: symbol)
        .onHover { hovering = $0 }
    }

    private var backgroundColor: Color {
        if prominent { return Color.white.opacity(hovering ? 1 : 0.92) }
        return Color.white.opacity(hovering ? 0.16 : 0)
    }
}

// MARK: - Nejbližší schůzka

struct NextEventCard: View {
    @EnvironmentObject private var calendar: CalendarMonitor
    @Environment(\.openURL) private var openURL

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .glassCard(padding: NotchLayout.spacingM)
    }

    @ViewBuilder
    private var content: some View {
        switch calendar.access {
        case .granted:
            if let e = calendar.nextMeeting {
                meeting(e)
            } else {
                emptyRow(symbol: "checkmark.circle", title: "Žádné další schůzky", subtitle: dayLongSubtitle)
            }
        case .unknown:
            VStack(alignment: .leading, spacing: 6) {
                Text("Kalendář")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                GlassPill(title: "Povolit přístup", symbol: "calendar.badge.plus") { calendar.requestAccess() }
            }
        case .denied:
            emptyRow(symbol: "lock.fill", title: "Kalendář bez přístupu", subtitle: "Povol ho v Nastavení → Soukromí")
        }
    }

    private func meeting(_ e: CalEvent) -> some View {
        let ongoing = e.start <= calendar.now
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ongoing ? "Právě probíhá" : "Další schůzka")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
                HStack(spacing: 6) {
                    Circle().fill(e.color).frame(width: 7, height: 7)
                    Text(e.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                }
                Text(whenText(e, ongoing: ongoing))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let url = e.joinURL {
                GlassIconButton(symbol: "video.fill", prominent: true, tint: Color.green.opacity(0.45),
                                size: NotchLayout.controlHeight) { openURL(url) }
                    .help("Připojit se")
            }
        }
    }

    private func emptyRow(symbol: String, title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.6))
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .lineLimit(1)
            }
        }
    }

    private var dayLongSubtitle: String? {
        guard let e = calendar.firstDayLongEvent else { return nil }
        return "Celý den: \(e.title)"
    }

    private func whenText(_ e: CalEvent, ongoing: Bool) -> String {
        if ongoing { return "do \(e.endText)" }
        if Calendar.current.isDateInToday(e.start) { return e.timeText }
        return "\(e.dayLabel) · \(e.startText)"
    }
}

// MARK: - Baterie

struct BatteryCard: View {
    @EnvironmentObject private var battery: BatteryMonitor
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .glassCard(padding: NotchLayout.spacingM)
    }

    @ViewBuilder
    private var content: some View {
        if battery.hasBattery {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Image(systemName: BatteryIcon.name(level: battery.level, charging: battery.isCharging))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(battery.isCharging ? Color.green : Color.white.opacity(0.8))
                    Text("\(battery.level) %")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                    Spacer(minLength: 0)
                }
                ThinProgress(value: Double(battery.level) / 100,
                             tint: battery.isCharging ? Color.green : settings.accent.color)
                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "powerplug.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
                Text("Napájení ze sítě")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
        }
    }

    private var statusText: String {
        if battery.isCharging {
            if let m = battery.minutesToFull { return "Nabíjí se · plná za \(m / 60) h \(m % 60) min" }
            return "Nabíjí se"
        }
        return battery.onAC ? "Zapojeno" : "Na baterii"
    }
}
