import AppKit
import SwiftUI

// MARK: - Jednotná zelená pro připojení kalendáře

/// Zelený akcent pro „Připojit kalendář“ / „Povolit přístup“ – stejný na Domů, v záložce Kalendář i v nastavení.
enum CalendarConnectStyle {
    static let accent = Color.green
    static let tint = Color.green.opacity(0.35)
}

// MARK: - Nastavení → Kalendář

/// Dva způsoby připojení kalendáře:
/// A) systémové kalendáře přes EventKit (iCloud, Google účet z Internetových účtů…),
/// B) přímé přihlášení ke Google Kalendáři (OAuth s vlastním Client ID).
struct CalendarSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var calendar: CalendarMonitor
    @ObservedObject private var google = GoogleCalendarService.shared

    private static let consoleURL = "https://console.cloud.google.com/apis/credentials"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            overviewCard
            systemCard
            if calendar.access == .granted {
                systemCalendarsCard
            }
            googleCard
            if google.isSignedIn && !google.calendars.isEmpty {
                googleCalendarsCard
            }
        }
        .onAppear {
            calendar.refreshAccess()
            google.refreshIfStale()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            calendar.refreshAccess()
        }
    }

    // MARK: Přehled

    private var overviewCard: some View {
        CalSettingsCard(header: "Zdroje událostí") {
            CalSettingsRow(title: "Kalendáře macOS") {
                CalStatusBadge(color: systemStatusColor, text: systemStatusText)
            }
            CalSettingsDivider()
            CalSettingsRow(title: "Google Kalendář (přímo)") {
                CalStatusBadge(color: google.isSignedIn ? Color.green : Color.white.opacity(0.35),
                            text: google.isSignedIn ? (google.email ?? "Připojeno") : "Nepřipojeno")
            }
        }
    }

    // MARK: A) Systémové kalendáře

    private var systemCard: some View {
        CalSettingsCard(header: "Kalendáře macOS") {
            CalSettingsRow(title: "Přístup ke kalendářům",
                           subtitle: "Kalendáře z aplikace Kalendář – iCloud, Exchange i Google účet přidaný do macOS.") {
                switch calendar.access {
                case .unknown:
                    GlassPill(title: "Povolit přístup", symbol: "checkmark",
                              tint: CalendarConnectStyle.tint) { calendar.requestAccess() }
                case .denied:
                    GlassPill(title: "Otevřít Soukromí", symbol: "arrow.up.forward") {
                        CalendarMonitor.openPrivacySettings()
                    }
                case .granted:
                    CalStatusBadge(color: Color.green, text: "Povoleno")
                }
            }
            if calendar.isWriteOnly {
                CalSettingsDivider()
                CalSettingsNote(symbol: "exclamationmark.triangle",
                                text: "NotchMax má od macOS jen přístup pro přidávání událostí, takže je nemůže číst. V Nastavení systému → Soukromí a zabezpečení → Kalendáře změň u NotchMax přístup na „Plný přístup“.")
            } else if calendar.access == .denied {
                CalSettingsDivider()
                CalSettingsNote(symbol: "lock",
                                text: "Přístup byl zamítnut. Povol ho v Nastavení systému → Soukromí a zabezpečení → Kalendáře. Nebo použij přímé přihlášení ke Googlu níže.")
            }
            CalSettingsDivider()
            CalSettingsRow(title: "Google účet v macOS",
                           subtitle: "Nejjednodušší cesta: v Nastavení systému → Internetové účty přidej Google a zapni u něj Kalendáře. Kalendáře se pak objeví tady.") {
                GlassPill(title: "Přidat Google účet", symbol: "person.crop.circle.badge.plus",
                          tint: CalendarConnectStyle.tint) {
                    CalendarMonitor.openInternetAccounts()
                }
            }
        }
    }

    private var systemCalendarsCard: some View {
        CalSettingsCard(header: "Zobrazené kalendáře macOS") {
            if calendar.calendarGroups.isEmpty {
                CalSettingsNote(symbol: "calendar",
                                text: "Zatím tu nejsou žádné kalendáře. Přidej účet v Internetových účtech nebo vytvoř kalendář v aplikaci Kalendář.")
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

    // MARK: B) Přímé přihlášení ke Googlu

    private var googleCard: some View {
        CalSettingsCard(header: "Google Kalendář – přímé přihlášení") {
            if google.isSignedIn {
                signedInContent
            } else {
                signInContent
            }
        }
    }

    @ViewBuilder
    private var signedInContent: some View {
        CalSettingsRow(title: "Účet", subtitle: google.email ?? "Přihlášeno") {
            HStack(spacing: 8) {
                GlassPill(title: "Obnovit", symbol: "arrow.clockwise") { google.refreshNow() }
                GlassPill(title: "Odhlásit", symbol: "rectangle.portrait.and.arrow.right") { google.signOut() }
            }
        }
        CalSettingsDivider()
        CalSettingsRow(title: "Poslední synchronizace", subtitle: "Události se načítají každých 5 minut.") {
            if google.isSyncing {
                ProgressView().controlSize(.small)
            } else {
                Text(google.lastSync.map { $0.formatted(date: .omitted, time: .shortened) } ?? "Zatím neproběhla")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        if let error = google.lastError {
            CalSettingsDivider()
            CalSettingsNote(symbol: "exclamationmark.triangle", text: error, tint: Color.orange)
        }
    }

    @ViewBuilder
    private var signInContent: some View {
        CalSettingsNote(symbol: "info.circle",
                        text: "Funguje i bez Internetových účtů v macOS. Potřebuješ vlastního OAuth klienta z Google Cloud Console – je zdarma a nastavuje se jednou (asi 5 minut).")
        CalSettingsDivider()
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(CalendarConnectStyle.accent)
                        .frame(width: 16, alignment: .trailing)
                    Text(step)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, 12)
        CalSettingsDivider()
        CalSettingsRow(title: "Google Cloud Console", subtitle: "APIs & Services → Credentials") {
            GlassPill(title: "Otevřít", symbol: "arrow.up.forward") {
                if let url = URL(string: Self.consoleURL) { NSWorkspace.shared.open(url) }
            }
        }
        CalSettingsDivider()
        CalSettingsRow(title: "Client ID") {
            CalCredentialField(placeholder: "…apps.googleusercontent.com", text: $google.clientID, secure: false)
        }
        CalSettingsDivider()
        CalSettingsRow(title: "Client secret") {
            CalCredentialField(placeholder: "GOCSPX-…", text: $google.clientSecret, secure: true)
        }
        CalSettingsDivider()
        HStack(spacing: 10) {
            if google.isSigningIn {
                ProgressView().controlSize(.small)
                Text("Dokonči přihlášení v prohlížeči…")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.7))
                Spacer(minLength: 8)
                GlassPill(title: "Zrušit", symbol: "xmark") { google.cancelSignIn() }
            } else {
                Spacer(minLength: 8)
                GlassPill(title: "Přihlásit se přes Google", symbol: "person.badge.key.fill",
                          tint: CalendarConnectStyle.tint) {
                    google.signIn()
                }
                .disabled(!google.hasCredentials)
                .opacity(google.hasCredentials ? 1 : 0.45)
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        if let error = google.lastError {
            CalSettingsDivider()
            CalSettingsNote(symbol: "exclamationmark.triangle", text: error, tint: Color.orange)
        }
    }

    private var googleCalendarsCard: some View {
        CalSettingsCard(header: "Zobrazené Google kalendáře") {
            ForEach(google.calendars) { item in
                CalCheckRow(title: item.isPrimary ? "\(item.title) (hlavní)" : item.title,
                                 color: item.color,
                                 isOn: visibilityBinding(GoogleCalendarService.hiddenKey(for: item.id)))
            }
            .padding(.vertical, 2)
            if calendar.access == .granted {
                CalSettingsDivider()
                CalSettingsNote(symbol: "square.on.square",
                                text: "Pokud máš stejný Google účet i v macOS, duplicitní události se zobrazí jen jednou.")
            }
        }
    }

    private static let steps: [String] = [
        "V Google Cloud Console vytvoř nový projekt (nebo vyber existující).",
        "APIs & Services → Library: vyhledej „Google Calendar API“ a klikni na Enable.",
        "OAuth consent screen (Google Auth Platform): typ External, vyplň název aplikace a svůj e-mail. V části Audience klikni na Publish app – v režimu Testing přihlášení vyprší po 7 dnech (případně se aspoň přidej do Test users).",
        "Credentials → Create credentials → OAuth client ID → Application type „Desktop app“ → Create.",
        "Zkopíruj Client ID a Client secret sem a klikni na „Přihlásit se přes Google“. Varování „Google tuto aplikaci neověřil“ přeskoč přes Pokročilé → Pokračovat – je to tvoje vlastní aplikace."
    ]

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
        if calendar.isWriteOnly { return "Jen zápis" }
        switch calendar.access {
        case .granted: return "Povoleno"
        case .denied: return "Zamítnuto"
        case .unknown: return "Zatím nepovoleno"
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

private struct CalCredentialField: View {
    let placeholder: String
    @Binding var text: String
    let secure: Bool

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 12.5, design: .monospaced))
        .foregroundStyle(Color.white)
        .padding(.horizontal, 10)
        .frame(width: 360, height: 28)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
        )
    }
}
