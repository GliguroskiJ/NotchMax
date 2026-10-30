import SwiftUI

/// Přehled: přehrávač + nejbližší událost + baterie.
struct HomeView: View {
    var body: some View {
        HStack(spacing: 12) {
            MediaCard()
            VStack(spacing: 10) {
                NextEventCard()
                BatteryCard()
            }
            .frame(width: 200)
        }
    }
}

struct MediaCard: View {
    @EnvironmentObject private var media: MediaMonitor
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Group {
            if media.hasTrack {
                HStack(spacing: 14) {
                    artwork
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(media.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            EqualizerBars(color: settings.accent.color, active: media.isPlaying)
                        }
                        Text(media.artist)
                            .font(.system(size: 12))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        controls
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(Color.white.opacity(0.4))
                    Text("Nic nehraje")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.6))
                    Text("Spusť Apple Music nebo Spotify")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .cardStyle()
    }

    private var artwork: some View {
        Group {
            if let art = media.artwork {
                Image(nsImage: art).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.08)
                    Image(systemName: "music.note").font(.system(size: 22)).foregroundStyle(Color.white.opacity(0.4))
                }
            }
        }
        .frame(width: 92, height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var controls: some View {
        GlassContainer(spacing: 10) {
            HStack(spacing: 10) {
                GlassIconButton(symbol: "backward.fill", size: 32) { media.previous() }
                GlassIconButton(symbol: media.isPlaying ? "pause.fill" : "play.fill",
                                prominent: true, tint: settings.accent.color.opacity(0.5), size: 38) {
                    media.togglePlayPause()
                }
                GlassIconButton(symbol: "forward.fill", size: 32) { media.next() }
            }
        }
    }
}

struct NextEventCard: View {
    @EnvironmentObject private var calendar: CalendarMonitor
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            switch calendar.access {
            case .granted:
                if let e = calendar.nextEvent {
                    HStack(spacing: 6) {
                        Circle().fill(e.color).frame(width: 7, height: 7)
                        Text(e.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .lineLimit(1)
                    }
                    Text(timeRange(e))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.6))
                    Spacer(minLength: 0)
                    if let url = e.joinURL {
                        GlassPill(title: "Připojit", symbol: "video.fill", tint: Color.green.opacity(0.4)) { openURL(url) }
                    }
                } else {
                    Label("Dnes volno", systemImage: "checkmark.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.6))
                }
            case .unknown:
                Text("Kalendář").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.white)
                Spacer(minLength: 0)
                GlassPill(title: "Povolit přístup", symbol: "calendar.badge.plus") { calendar.requestAccess() }
            case .denied:
                Text("Kalendář bez přístupu").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.white)
                Text("Povol ho v Nastavení → Soukromí")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .cardStyle()
    }

    private func timeRange(_ e: CalEvent) -> String {
        if e.isAllDay { return "Celý den" }
        let f = e.start.formatted(date: .omitted, time: .shortened)
        let t = e.end.formatted(date: .omitted, time: .shortened)
        return "\(f) – \(t)"
    }
}

struct BatteryCard: View {
    @EnvironmentObject private var battery: BatteryMonitor
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if battery.hasBattery {
                HStack {
                    Image(systemName: battery.isCharging ? "bolt.fill" : "battery.75percent")
                        .foregroundStyle(battery.isCharging ? Color.green : Color.white.opacity(0.7))
                    Text("\(battery.level) %")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                    Spacer()
                }
                ProgressView(value: Double(battery.level), total: 100)
                    .tint(battery.isCharging ? Color.green : settings.accent.color)
                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .lineLimit(1)
            } else {
                Label("Napájení ze sítě", systemImage: "powerplug.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
        }
        .cardStyle()
    }

    private var statusText: String {
        if battery.isCharging {
            if let m = battery.minutesToFull { return "Nabíjí se · plná za \(m / 60) h \(m % 60) min" }
            return "Nabíjí se"
        }
        return battery.onAC ? "Zapojeno" : "Na baterii"
    }
}
