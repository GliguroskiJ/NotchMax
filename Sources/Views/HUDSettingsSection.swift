import SwiftUI
import AppKit

/// Sekce nastavení „HUD a oznámení“ – náhrada systémových HUD, animace v notchi,
/// zrcadlení oznámení a tlačítko zrcátka.
struct HUDSettingsSection: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var mirror = NotificationMirror.shared
    @ObservedObject private var focusMonitor = FocusModeMonitor.shared

    @State private var accessibilityTrusted: Bool = false
    @State private var focusCanRead: Bool = true
    @State private var fullDiskAccess: Bool = false

    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            volumeCard
            animationsCard
            notificationsCard
            mirrorCard
        }
        .onAppear { refreshPermissions() }
        .onReceive(refreshTimer) { _ in refreshPermissions() }
    }

    private func refreshPermissions() {
        let trusted = MediaKeyInterceptor.shared.isTrusted
        if trusted != accessibilityTrusted { accessibilityTrusted = trusted }
        let canRead = FocusModeMonitor.shared.canRead
        if canRead != focusCanRead { focusCanRead = canRead }
        let fda = NotificationMirror.shared.hasFullDiskAccess
        if fda != fullDiskAccess { fullDiskAccess = fda }
    }

    // MARK: Hlasitost a jas

    private var volumeCard: some View {
        SettingsCard(header: "Hlasitost a jas") {
            SettingsToggleRow(title: "Nahradit systémové HUD",
                              subtitle: "Hlasitost, jas displeje a podsvícení klávesnice se zobrazí v notchi místo uprostřed obrazovky.",
                              isOn: $settings.hudReplaceSystem)
            SettingsDivider()
            SettingsRow(title: "Zpřístupnění",
                        subtitle: accessibilityTrusted
                            ? "NotchMax může zachytávat mediální klávesy."
                            : "Bez oprávnění Zpřístupnění se systémové HUD nedá nahradit.") {
                if accessibilityTrusted {
                    HUDStatusBadge(text: "Povoleno", color: .green)
                } else {
                    HStack(spacing: 8) {
                        Button("Povolit přístupnost") {
                            MediaKeyInterceptor.shared.requestAccess()
                        }
                        .controlSize(.regular)
                        GlassPill(title: "Otevřít nastavení", symbol: "gearshape") {
                            MediaKeyInterceptor.shared.openAccessibilitySettings()
                        }
                    }
                }
            }
            SettingsDivider()
            SettingsNote(symbol: "info.circle",
                         text: "Aplikace není podepsaná vývojářským certifikátem, takže macOS může po každé aktualizaci NotchMaxu oprávnění zneplatnit. Pokud HUD přestane fungovat, odeber NotchMax v Nastavení systému → Soukromí a zabezpečení → Zpřístupnění a povol ho znovu.")
        }
    }

    // MARK: Animace

    private var animationsCard: some View {
        SettingsCard(header: "Animace") {
            SettingsToggleRow(title: "Přehrávání – play, pauza, další, předchozí",
                              subtitle: "Krátká animace v notchi při ovládání přehrávání.",
                              isOn: $settings.hudMedia)
            SettingsDivider()
            SettingsToggleRow(title: "Připojení AirPods a sluchátek",
                              subtitle: "Při prvním zapnutí se macOS zeptá na přístup k Bluetooth.",
                              isOn: $settings.hudHeadphones)
            SettingsDivider()
            SettingsToggleRow(title: "Přepnutí soustředění",
                              subtitle: "Ukáže v notchi, když zapneš nebo vypneš režim soustředění.",
                              isOn: $settings.hudFocus)
            if settings.hudFocus && !focusCanRead {
                SettingsDivider()
                SettingsRow(title: "Chybí plný přístup k disku",
                            subtitle: "Stav soustředění macOS ukládá do chráněné složky – NotchMax ho přečte jen s plným přístupem k disku.") {
                    GlassPill(title: "Otevřít nastavení", symbol: "lock.open") {
                        NotificationMirror.shared.openFullDiskAccessSettings()
                    }
                }
            }
            SettingsDivider()
            SettingsToggleRow(title: "Claude agenti – hotovo / čeká na tebe",
                              subtitle: "Upozorní v notchi, když agent dokončí práci nebo potřebuje tvoje rozhodnutí.",
                              isOn: $settings.hudClaude)
        }
    }

    // MARK: Oznámení

    private var notificationsCard: some View {
        SettingsCard(header: "Oznámení v notchi (experimentální)") {
            SettingsToggleRow(title: "Zobrazovat oznámení v notchi",
                              subtitle: "Nová oznámení z aplikací se ukážou jako krátká animace v notchi.",
                              isOn: $settings.hudNotifications)
            SettingsDivider()
            SettingsRow(title: "Stav", subtitle: mirror.status.description) {
                HUDStatusBadge(text: fullDiskAccess ? "Plný přístup k disku" : "Bez přístupu k disku",
                            color: fullDiskAccess ? .green : .orange)
            }
            SettingsDivider()
            SettingsRow(title: "Oprávnění a nastavení") {
                HStack(spacing: 8) {
                    if !fullDiskAccess {
                        GlassPill(title: "Udělit plný přístup k disku", symbol: "lock.open") {
                            NotificationMirror.shared.openFullDiskAccessSettings()
                        }
                    }
                    GlassPill(title: "Nastavení oznámení", symbol: "bell") {
                        NotificationMirror.shared.openNotificationSettings()
                    }
                }
            }
            SettingsDivider()
            SettingsNote(symbol: "list.number",
                         text: "Jak to nastavit:\n1) Povol plný přístup k disku pro NotchMax (Nastavení systému → Soukromí a zabezpečení → Plný přístup k disku).\n2) V Nastavení systému → Oznámení nastav u vybraných aplikací styl upozornění „Žádné“. Zprávy pak chodí jen do notche a v Centru oznámení zůstanou.\n3) Zapni přepínač výše.")
            SettingsDivider()
            SettingsNote(symbol: "exclamationmark.triangle",
                         text: "macOS neumožňuje systémové bannery automaticky vypnout ani plně nahradit. NotchMax oznámení jen čte z databáze Centra oznámení, takže se mohou objevit s malým zpožděním a bez akcí (odpovědět, označit apod.). Pokud styl upozornění nezměníš, uvidíš oznámení dvakrát.")
        }
    }

    // MARK: Zrcátko

    private var mirrorCard: some View {
        SettingsCard(header: "Zrcátko") {
            SettingsToggleRow(title: "Tlačítko kamery v notchi",
                              subtitle: "Rychlý náhled z kamery – zkontroluj se před hovorem.",
                              isOn: $settings.mirrorButton)
        }
    }
}

/// Malý štítek se stavem (barevná tečka + text).
private struct HUDStatusBadge: View {
    let text: String
    let color: Color

    init(text: String, color: Color) {
        self.text = text
        self.color = color
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.75))
        }
    }
}
