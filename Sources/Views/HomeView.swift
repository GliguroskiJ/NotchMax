import SwiftUI

/// Přehled: přehrávač + nejbližší schůzka + baterie.
struct HomeView: View {
    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = NotchLayout.spacingM
            let available: CGFloat = max(geo.size.width - spacing, 0)
            // Přehrávač ~58 % šířky, kalendář a baterie zbytek – pružně podle šířky panelu.
            let playerWidth: CGFloat = (available * MediaCard.widthFraction).rounded()
            HStack(spacing: spacing) {
                MediaCard()
                    .frame(width: playerWidth)
                VStack(spacing: spacing) {
                    NextEventCard()
                    BatteryCard()
                }
                .frame(maxWidth: .infinity)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Přehrávač

struct MediaCard: View {
    @EnvironmentObject private var media: MediaMonitor
    @EnvironmentObject private var settings: AppSettings

    /// Podíl šířky Přehledu, který dostane karta přehrávače.
    static let widthFraction: CGFloat = 0.58
    private let artSize: CGFloat = 116

    var body: some View {
        Group {
            if media.hasTrack {
                player
            } else {
                EmptyState(symbol: "music.note", title: L("Nic nehraje"), message: L("Spusť Apple Music nebo Spotify"))
            }
        }
        .glassCard(padding: 10)
        .animation(.smooth(duration: 0.3), value: media.hasTrack)
    }

    private var player: some View {
        HStack(alignment: .center, spacing: NotchLayout.spacingM) {
            artwork
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Image(systemName: "music.note")
                        .font(.system(size: 9, weight: .bold))
                    Text(media.source?.appName ?? "")
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    EqualizerBars(color: settings.accent.color, active: media.isPlaying)
                }
                .foregroundStyle(Color.white.opacity(0.45))

                Text(media.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 6)
                    .help(media.title)
                Text(media.artist)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 2)

                // Tlačítka uprostřed zbývajícího prostoru pod názvem (svisle i vodorovně).
                Spacer(minLength: 6)
                controls
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer(minLength: 6)
            }
            .padding(.vertical, 4)
            .padding(.trailing, 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
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

    /// Tři samostatná kulatá skleněná tlačítka (bez společné kapsle), play/pauza větší a zvýrazněné.
    private var controls: some View {
        HStack(spacing: 8) {
            GlassTransportButton(symbol: "backward.fill", size: 30) { media.previous() }
                .help(L("Předchozí"))
            GlassTransportButton(symbol: media.isPlaying ? "pause.fill" : "play.fill", size: 40,
                                 prominent: true, tint: settings.accent.color.opacity(0.45)) {
                media.togglePlayPause()
            }
            .help(media.isPlaying ? L("Pozastavit") : L("Přehrát"))
            GlassTransportButton(symbol: "forward.fill", size: 30) { media.next() }
                .help(L("Další"))
        }
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
            .contentShape(Rectangle())
            .onTapGesture {
                if let url = calendar.nextMeeting?.joinURL { openURL(url) }
            }
    }

    @ViewBuilder
    private var content: some View {
        if calendar.hasAnySource {
            if let e = calendar.nextMeeting {
                meeting(e)
            } else {
                emptyRow(symbol: "checkmark.circle", title: L("Žádné další schůzky"), subtitle: dayLongSubtitle)
            }
        } else {
            // Není připojený žádný zdroj – nastavení nabídne připojení kalendářů macOS.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(CalendarConnectStyle.accent)
                    Text(L("Kalendář"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
                GlassPill(title: L("Připojit kalendář"), symbol: "calendar.badge.plus",
                          tint: CalendarConnectStyle.tint) { openNotchMaxSettings(section: "calendar") }
            }
        }
    }

    private func meeting(_ e: CalEvent) -> some View {
        let ongoing = e.start <= Date()
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(ongoing ? L("Právě probíhá") : L("Další schůzka"))
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
                    .help(L("Připojit se"))
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
        let now = Date()
        guard let e = calendar.events.first(where: { $0.isAllDay && $0.end > now }) else { return nil }
        return L("Celý den: %@", e.title)
    }

    private func whenText(_ e: CalEvent, ongoing: Bool) -> String {
        if ongoing { return L("do %@", e.endText) }
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
                    .minimumScaleFactor(0.75)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "powerplug.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
                Text(L("Napájení ze sítě"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
        }
    }

    private var statusText: String {
        if battery.isCharging {
            if let m = battery.minutesToFull { return L("Nabíjí se · plná za %d h %d min", m / 60, m % 60) }
            return L("Nabíjí se")
        }
        return battery.onAC ? L("Zapojeno") : L("Na baterii")
    }
}
