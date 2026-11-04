import AppKit
import SwiftUI

// MARK: - Jednotná zelená pro připojení kalendáře

/// Zelený akcent pro „Připojit kalendář“ / „Povolit přístup“ – stejný na Domů, v záložce Kalendář i v nastavení.
enum CalendarConnectStyle {
    static let accent = Color.green
    static let tint = Color.green.opacity(0.35)
}

// MARK: - Nastavení → Kalendář

/// Kalendáře macOS přes EventKit (iCloud, Exchange, Google účet z Internetových účtů…).
struct CalendarSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var calendar: CalendarMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            accessCard
            if calendar.access == .granted {
                calendarsCard
            }
        }
        .onAppear {
            calendar.refreshAccess()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            calendar.refreshAccess()
        }
    }

    // MARK: Přístup a účty

    private var accessCard: some View {
        CalSettingsCard(header: L("Kalendáře macOS")) {
            CalSettingsRow(title: L("Přístup ke kalendářům"),
                           subtitle: L("Kalendáře z aplikace Kalendář – iCloud, Exchange i Google účet přidaný do macOS.")) {
                HStack(spacing: 10) {
                    CalStatusBadge(color: systemStatusColor, text: systemStatusText)
                    switch calendar.access {
                    case .unknown:
                        GlassPill(title: L("Povolit přístup"), symbol: "checkmark",
                                  tint: CalendarConnectStyle.tint) { calendar.requestAccess() }
                    case .denied:
                        GlassPill(title: L("Otevřít nastavení"), symbol: "arrow.up.forward",
                                  tint: CalendarConnectStyle.tint) {
                            CalendarMonitor.openPrivacySettings()
                        }
                    case .granted:
                        EmptyView()
                    }
                }
                .fixedSize()
            }
            if calendar.isWriteOnly {
                CalSettingsDivider()
                CalSettingsNote(symbol: "exclamationmark.triangle",
                                text: L("NotchMax má od macOS jen přístup pro přidávání událostí, takže je nemůže číst. V Nastavení systému → Soukromí a zabezpečení → Kalendáře změň u NotchMax přístup na „Plný přístup“."))
            } else if calendar.access == .denied {
                CalSettingsDivider()
                CalSettingsNote(symbol: "lock",
                                text: L("Přístup byl zamítnut. Povol ho v Nastavení systému → Soukromí a zabezpečení → Kalendáře."))
            }
            CalSettingsDivider()
            CalSettingsRow(title: L("Google účet"),
                           subtitle: L("V Internetových účtech přidej Google a zapni u něj Kalendáře – objeví se tady.")) {
                GlassPill(title: L("Přidat Google účet"), symbol: "person.crop.circle.badge.plus",
                          tint: CalendarConnectStyle.tint) {
                    CalendarMonitor.openInternetAccounts()
                }
                .fixedSize()
            }
        }
    }

    // MARK: Výběr kalendářů

    private var calendarsCard: some View {
        CalSettingsCard(header: L("Zobrazené kalendáře")) {
            if calendar.calendarGroups.isEmpty {
                CalSettingsNote(symbol: "calendar",
                                text: L("Zatím tu nejsou žádné kalendáře. Přidej účet v Internetových účtech nebo vytvoř kalendář v aplikaci Kalendář."))
            } else {
                ForEach(Array(calendar.calendarGroups.enumerated()), id: \.element.id) { index, group in
                    if index > 0 { CalSettingsDivider() }
                    CalGroupHeader(title: group.title, subtitle: group.subtitle)
                    ForEach(group.calendars) { item in
                        CalCheckRow(title: item.title, color: item.color,
                                    isOn: visibilityBinding(item.id))
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }

    // MARK: Pomocné

    private func visibilityBinding(_ key: String) -> Binding<Bool> {
        Binding<Bool>(
            get: { !settings.hiddenCalendarIDs.contains(key) },
            set: { visible in
                var ids = settings.hiddenCalendarIDs
                ids.removeAll { $0 == key }
                if !visible { ids.append(key) }
                settings.hiddenCalendarIDs = ids
            }
        )
    }

    private var systemStatusText: String {
        if calendar.isWriteOnly { return L("Jen zápis") }
        switch calendar.access {
        case .granted: return L("Povoleno")
        case .denied: return L("Zamítnuto")
        case .unknown: return L("Zatím nepovoleno")
        }
    }

    private var systemStatusColor: Color {
        switch calendar.access {
        case .granted: return Color.green
        case .denied: return Color.red
        case .unknown: return Color.orange
        }
    }
}

// MARK: - Komponenty (vzhled odpovídá kartám v SettingsView)

private struct CalSettingsCard<Content: View>: View {
    var header: String?
    let content: () -> Content

    init(header: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.header = header
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let header {
                Text(header.uppercased())
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .padding(.horizontal, 4)
            }
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.75)
            )
        }
    }
}

private struct CalSettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
    }
}

private struct CalSettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    let trailing: () -> Trailing

    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Color.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }
}

private struct CalSettingsNote: View {
    let symbol: String
    let text: String
    var tint: Color = Color.white.opacity(0.5)

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(.vertical, 12)
    }
}

private struct CalStatusBadge: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 13.5))
                .foregroundStyle(Color.white.opacity(0.7))
                .lineLimit(1)
        }
    }
}

private struct CalGroupHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.85))
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 12)
        .padding(.bottom, 2)
    }
}

private struct CalCheckRow: View {
    let title: String
    let color: Color
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                Text(title)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.white.opacity(isOn ? 1 : 0.5))
                    .lineLimit(1)
            }
            .padding(.leading, 4)
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
