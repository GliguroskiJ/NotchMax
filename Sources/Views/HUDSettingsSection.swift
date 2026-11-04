import SwiftUI
import AppKit
import AVFoundation
import EventKit
import CoreBluetooth
import UserNotifications

// MARK: - Oprávnění: model

/// Systémová oprávnění, která NotchMax používá.
enum PermissionKind: String, CaseIterable, Identifiable {
    case accessibility, fullDiskAccess, calendar, camera, bluetooth, notifications

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: return "Zpřístupnění"
        case .fullDiskAccess: return "Plný přístup k disku"
        case .calendar: return "Kalendář"
        case .camera: return "Kamera"
        case .bluetooth: return "Bluetooth"
        case .notifications: return "Oznámení"
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: return "accessibility"
        case .fullDiskAccess: return "externaldrive.fill"
        case .calendar: return "calendar"
        case .camera: return "camera.fill"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .notifications: return "bell.fill"
        }
    }

    /// K čemu oprávnění NotchMax potřebuje.
    var purpose: String {
        switch self {
        case .accessibility:
            return "HUD hlasitosti a jasu v notchi a přepínání Nerušit s časovačem."
        case .fullDiskAccess:
            return "Oznámení v notchi a zobrazení přepnutí Soustředění. Nedá se vyžádat dialogem – v seznamu zapni NotchMax, a když tam není, přidej ho tlačítkem (+)."
        case .calendar:
            return "Nadcházející události v notchi a v záložce Kalendář."
        case .camera:
            return "Zrcátko – náhled z kamery v notchi."
        case .bluetooth:
            return "Animace při připojení AirPods a sluchátek."
        case .notifications:
            return "Systémová upozornění od samotného NotchMaxu. Pro zobrazování oznámení v notchi potřeba není."
        }
    }

    /// Otevře příslušný panel Nastavení systému.
    @MainActor
    func openSystemSettings() {
        switch self {
        case .accessibility: SystemSettingsLink.open(.accessibility)
        case .fullDiskAccess: SystemSettingsLink.open(.fullDiskAccess)
        case .calendar: SystemSettingsLink.open(.calendars)
        case .camera: SystemSettingsLink.open(.camera)
        case .bluetooth: SystemSettingsLink.open(.bluetooth)
        case .notifications: SystemSettingsLink.open(.notifications)
        }
    }
}

/// Stav jednoho oprávnění.
enum PermissionState: Equatable {
    case granted, partial, missing, notDetermined, unknown

    var title: String {
        switch self {
        case .granted: return "Povoleno"
        case .partial: return "Jen částečně"
        case .missing: return "Chybí"
        case .notDetermined: return "Nevyžádáno"
        case .unknown: return "Zjišťuji…"
        }
    }

    var color: Color {
        switch self {
        case .granted: return .green
        case .partial: return .yellow
        case .missing: return .orange
        case .notDetermined: return Color.white.opacity(0.45)
        case .unknown: return Color.white.opacity(0.3)
        }
    }
}

/// Delegát pro CBCentralManager – jeho vytvoření vyvolá systémový dotaz na Bluetooth.
private final class BluetoothPermissionProbe: NSObject, CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            PermissionCenter.shared.refresh()
        }
    }
}

/// Živý přehled stavu oprávnění (obnovuje se z okna nastavení každé 2 s).
@MainActor
final class PermissionCenter: ObservableObject {
    static let shared = PermissionCenter()

    @Published private(set) var states: [PermissionKind: PermissionState] = [:]

    private var bluetoothProbe: BluetoothPermissionProbe?
    private var bluetoothManager: CBCentralManager?

    private init() {}

    func state(_ kind: PermissionKind) -> PermissionState {
        states[kind] ?? .unknown
    }

    /// Jestli je oprávnění potřeba pro aktuálně zapnuté funkce.
    func isNeeded(_ kind: PermissionKind) -> Bool {
        let s = AppSettings.shared
        switch kind {
        case .accessibility: return s.hudReplaceSystem || s.focusWithTimer
        case .fullDiskAccess: return s.hudNotifications || s.hudFocus
        case .calendar: return s.liveCalendar || s.tabCalendar
        case .camera: return s.mirrorButton
        case .bluetooth: return s.hudHeadphones
        case .notifications: return false
        }
    }

    /// Počet oprávnění, která zapnuté funkce potřebují, ale chybí.
    var missingCount: Int {
        PermissionKind.allCases.filter { kind in
            let st = state(kind)
            return isNeeded(kind) && (st == .missing || st == .partial)
        }.count
    }

    func refresh() {
        var next = states
        next[.accessibility] = MediaKeyInterceptor.shared.isTrusted ? .granted : .missing
        next[.fullDiskAccess] = NotificationMirror.shared.hasFullDiskAccess ? .granted : .missing
        next[.calendar] = Self.calendarState()
        next[.camera] = Self.cameraState()
        next[.bluetooth] = Self.bluetoothState()
        if next != states { states = next }

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                PermissionCenter.shared.applyNotificationStatus(status)
            }
        }
    }

    private func applyNotificationStatus(_ status: UNAuthorizationStatus) {
        let value: PermissionState
        switch status {
        case .authorized, .provisional: value = .granted
        case .notDetermined: value = .notDetermined
        case .denied: value = .missing
        @unknown default: value = .unknown
        }
        if states[.notifications] != value { states[.notifications] = value }
    }

    /// Jde oprávnění vyžádat systémovým dialogem?
    func canPrompt(_ kind: PermissionKind) -> Bool {
        switch kind {
        case .accessibility: return state(kind) != .granted
        case .fullDiskAccess: return false
        case .calendar, .camera, .bluetooth, .notifications: return state(kind) == .notDetermined
        }
    }

    /// Vyžádá oprávnění dialogem; když to nejde, otevře Nastavení systému.
    func request(_ kind: PermissionKind) {
        switch kind {
        case .accessibility:
            MediaKeyInterceptor.shared.requestAccess()
        case .fullDiskAccess:
            kind.openSystemSettings()
        case .calendar:
            if state(kind) == .notDetermined {
                AppServices.shared.calendar.requestAccess()
            } else {
                kind.openSystemSettings()
            }
        case .camera:
            if state(kind) == .notDetermined {
                AVCaptureDevice.requestAccess(for: .video) { _ in
                    Task { @MainActor in
                        PermissionCenter.shared.refresh()
                    }
                }
            } else {
                kind.openSystemSettings()
            }
        case .bluetooth:
            if state(kind) == .notDetermined {
                let probe = BluetoothPermissionProbe()
                bluetoothProbe = probe
                bluetoothManager = CBCentralManager(delegate: probe, queue: nil)
            } else {
                kind.openSystemSettings()
            }
        case .notifications:
            if state(kind) == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
                    Task { @MainActor in
                        PermissionCenter.shared.refresh()
                    }
                }
            } else {
                kind.openSystemSettings()
            }
        }
        refresh()
    }

    /// Ukáže NotchMax.app ve Finderu (aby šla přetáhnout do seznamu v Nastavení systému).
    func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    private static func calendarState() -> PermissionState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .writeOnly: return .partial
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .missing
        @unknown default: return .unknown
        }
    }

    private static func cameraState() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .missing
        @unknown default: return .unknown
        }
    }

    private static func bluetoothState() -> PermissionState {
        switch CBManager.authorization {
        case .allowedAlways: return .granted
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .missing
        @unknown default: return .unknown
        }
    }
}

// MARK: - Oprávnění: prvky UI

/// Štítek se stavem (barevná tečka + text).
struct PermissionStatusBadge: View {
    let text: String
    let color: Color

    init(text: String, color: Color) {
        self.text = text
        self.color = color
    }

    init(state: PermissionState) {
        self.text = state.title
        self.color = state.color
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.75))
                .lineLimit(1)
        }
        .fixedSize()
    }
}

/// Řádek jednoho oprávnění: stav + funkční tlačítka (na vlastním řádku, nikdy se neořežou).
/// `compact` = vložený do jiné sekce: tlačítka jen když oprávnění chybí, plus odkaz na přehled.
struct PermissionRow: View {
    let kind: PermissionKind
    let compact: Bool
    @ObservedObject private var center = PermissionCenter.shared
    @EnvironmentObject private var settings: AppSettings

    init(kind: PermissionKind, compact: Bool = false) {
        self.kind = kind
        self.compact = compact
    }

    private var state: PermissionState { center.state(kind) }

    private var subtitle: String {
        if kind == .calendar && state == .partial {
            return "Povolen je jen zápis – NotchMax potřebuje plný přístup ke kalendářům."
        }
        return kind.purpose
    }

    private var showsButtons: Bool {
        !compact || state != .granted
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !compact {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(settings.accent.color.opacity(0.18))
                    Image(systemName: kind.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(settings.accent.color)
                }
                .frame(width: 28, height: 28)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(compact ? "Oprávnění: \(kind.title)" : kind.title)
                            .font(.system(size: 14.5))
                            .foregroundStyle(Color.white)
                        Text(subtitle)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    PermissionStatusBadge(state: state)
                        .padding(.top, 2)
                }

                if showsButtons {
                    SettingsButtonRow {
                        if center.canPrompt(kind) {
                            GlassPill(title: "Povolit", symbol: "hand.raised.fill",
                                      tint: settings.accent.color.opacity(0.35)) {
                                center.request(kind)
                            }
                            .fixedSize()
                        }
                        GlassPill(title: "Otevřít Nastavení", symbol: "arrow.up.forward.app") {
                            kind.openSystemSettings()
                        }
                        .fixedSize()
                        if (kind == .fullDiskAccess || kind == .accessibility) && state != .granted {
                            GlassPill(title: "Ukázat ve Finderu", symbol: "folder") {
                                center.revealAppInFinder()
                            }
                            .fixedSize()
                        }
                        if compact {
                            GlassPill(title: "Všechna oprávnění", symbol: "lock.shield") {
                                showSettingsSection(.permissions)
                            }
                            .fixedSize()
                        }
                    }
                }
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { center.refresh() }
    }
}

// MARK: - Sekce „Oprávnění“

struct PermissionsSettingsSection: View {
    @ObservedObject private var center = PermissionCenter.shared

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(header: "Přehled") {
                ForEach(Array(PermissionKind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 { SettingsDivider() }
                    PermissionRow(kind: kind)
                }
            }

            SettingsCard(header: "Když oprávnění nefunguje") {
                SettingsNote(symbol: "exclamationmark.triangle",
                             text: "Přepínač v Nastavení systému je zapnutý, ale tady svítí „Chybí“? Vyber NotchMax v seznamu, odeber ho tlačítkem (−) a přidej znovu tlačítkem (+) – nebo ho do seznamu přetáhni z Finderu. Potom NotchMax restartuj.")
                SettingsDivider()
                SettingsNote(symbol: "signature",
                             text: "Po každé aktualizaci nepodepsaného sestavení může macOS udělená oprávnění zapomenout, protože aplikaci pozná podle podpisu. Trvalé řešení je stabilní podpisový certifikát – viz README a skript scripts/create-signing-cert.sh.")
                SettingsDivider()
                SettingsActionRow(title: "Akce") {
                    GlassPill(title: "Zkontrolovat znovu", symbol: "arrow.clockwise") {
                        center.refresh()
                    }
                    .fixedSize()
                    GlassPill(title: "Ukázat NotchMax ve Finderu", symbol: "folder") {
                        center.revealAppInFinder()
                    }
                    .fixedSize()
                    GlassPill(title: "Ukončit NotchMax", symbol: "power") {
                        NSApp.terminate(nil)
                    }
                    .fixedSize()
                }
            }
        }
        .onAppear { center.refresh() }
    }
}

// MARK: - Sekce „Notch“: HUD a animace

/// HUD hlasitosti a jasu a animace v notchi (média, AirPods, Soustředění, Claude).
struct HUDSettingsSection: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var focusMonitor = FocusModeMonitor.shared
    @ObservedObject private var center = PermissionCenter.shared

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(header: "HUD hlasitosti a jasu") {
                SettingsToggleRow(title: "Nahradit systémové HUD",
                                  subtitle: "Hlasitost, jas displeje a podsvícení klávesnice se zobrazí v notchi místo uprostřed obrazovky.",
                                  isOn: $settings.hudReplaceSystem)
                if settings.hudReplaceSystem {
                    SettingsDivider()
                    PermissionRow(kind: .accessibility, compact: true)
                }
            }

            SettingsCard(header: "Animace v notchi") {
                SettingsToggleRow(title: "Přehrávání médií",
                                  subtitle: "Krátká animace při play, pauze, další a předchozí skladbě.",
                                  isOn: $settings.hudMedia)
                SettingsDivider()
                SettingsToggleRow(title: "AirPods a sluchátka",
                                  subtitle: "Animace při připojení s ukazatelem baterie.",
                                  isOn: $settings.hudHeadphones)
                if settings.hudHeadphones && center.state(.bluetooth) == .missing {
                    SettingsDivider()
                    PermissionRow(kind: .bluetooth, compact: true)
                }
                SettingsDivider()
                SettingsToggleRow(title: "Soustředění",
                                  subtitle: "Ukáže v notchi, když zapneš nebo vypneš režim soustředění.",
                                  isOn: $settings.hudFocus)
                if settings.hudFocus && !focusMonitor.canRead {
                    SettingsDivider()
                    PermissionRow(kind: .fullDiskAccess, compact: true)
                }
                SettingsDivider()
                SettingsToggleRow(title: "Claude agenti – hotovo / čeká na tebe",
                                  subtitle: "Upozorní v notchi, když agent dokončí práci nebo potřebuje tvoje rozhodnutí.",
                                  isOn: $settings.hudClaude)
            }
        }
    }
}

// MARK: - Sekce „Oznámení“

struct NotificationSettingsSection: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var mirror = NotificationMirror.shared

    init() {}

    private var statusBadge: PermissionStatusBadge {
        switch mirror.status {
        case .disabled: return PermissionStatusBadge(text: "Vypnuto", color: Color.white.opacity(0.4))
        case .needsFullDiskAccess: return PermissionStatusBadge(text: "Chybí přístup", color: .orange)
        case .running: return PermissionStatusBadge(text: "Běží", color: .green)
        case .unsupported: return PermissionStatusBadge(text: "Nedostupné", color: .orange)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(header: "Oznámení v notchi (experimentální)") {
                SettingsToggleRow(title: "Zobrazovat oznámení v notchi",
                                  subtitle: "Nová oznámení z aplikací se ukážou jako krátká animace v notchi.",
                                  isOn: $settings.hudNotifications)
                SettingsDivider()
                SettingsRow(title: "Stav", subtitle: mirror.status.description) {
                    statusBadge
                }
                SettingsDivider()
                PermissionRow(kind: .fullDiskAccess, compact: true)
            }

            SettingsCard(header: "Vyzkoušet") {
                SettingsActionRow(title: "Test oznámení",
                                  subtitle: "Testovací oznámení projde celou cestou přes Centrum oznámení; náhled jen ukáže, jak oznámení v notchi vypadá.") {
                    GlassPill(title: "Poslat testovací oznámení", symbol: "paperplane.fill",
                              tint: settings.accent.color.opacity(0.35)) {
                        mirror.sendTestNotification()
                    }
                    .fixedSize()
                    GlassPill(title: "Ukázat náhled", symbol: "eye") {
                        mirror.previewNotificationHUD()
                    }
                    .fixedSize()
                }
                if let result = mirror.lastTestResult, !result.isEmpty {
                    SettingsDivider()
                    SettingsNote(symbol: "text.bubble", text: result)
                }
            }

            SettingsCard(header: "Jak to nastavit") {
                SettingsNote(symbol: "list.number",
                             text: "1) Povol NotchMaxu plný přístup k disku (sekce Oprávnění).\n2) V Nastavení systému → Oznámení nastav u vybraných aplikací styl upozornění „Žádné“. Zprávy pak chodí jen do notche a v Centru oznámení zůstanou.\n3) Zapni přepínač výše.")
                SettingsDivider()
                SettingsActionRow(title: "Nastavení oznámení v macOS") {
                    GlassPill(title: "Otevřít Oznámení", symbol: "bell") {
                        SystemSettingsLink.open(.notifications)
                    }
                    .fixedSize()
                }
                SettingsDivider()
                SettingsNote(symbol: "exclamationmark.triangle",
                             text: "macOS neumožňuje systémové bannery automaticky vypnout ani plně nahradit. NotchMax oznámení jen čte z databáze Centra oznámení, takže se mohou objevit s malým zpožděním a bez akcí (odpovědět, označit apod.). Pokud styl upozornění nezměníš, uvidíš oznámení dvakrát.")
            }
        }
    }
}
