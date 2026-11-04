import SwiftUI
import AppKit
import AVFoundation
import EventKit
import CoreBluetooth

// MARK: - Oprávnění: model

/// Systémová oprávnění, která NotchMax používá.
enum PermissionKind: String, CaseIterable, Identifiable {
    case accessibility, fullDiskAccess, calendar, camera, bluetooth

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: return L("Zpřístupnění")
        case .fullDiskAccess: return L("Plný přístup k disku")
        case .calendar: return L("Kalendář")
        case .camera: return L("Kamera")
        case .bluetooth: return L("Bluetooth")
        }
    }

    var symbol: String {
        switch self {
        case .accessibility: return "accessibility"
        case .fullDiskAccess: return "externaldrive.fill"
        case .calendar: return "calendar"
        case .camera: return "camera.fill"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        }
    }

    /// K čemu oprávnění NotchMax potřebuje.
    var purpose: String {
        switch self {
        case .accessibility:
            return L("HUD hlasitosti a jasu v notchi a přepínání Nerušit s časovačem.")
        case .fullDiskAccess:
            return L("Rozpoznání zapnutí a vypnutí režimu Soustředění (animace v notchi). Nedá se vyžádat dialogem – v seznamu zapni NotchMax, a když tam není, přidej ho tlačítkem (+).")
        case .calendar:
            return L("Nadcházející události v notchi a v záložce Kalendář.")
        case .camera:
            return L("Zrcátko – náhled z kamery v notchi.")
        case .bluetooth:
            return L("Animace při připojení AirPods a sluchátek.")
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
        }
    }
}

/// Stav jednoho oprávnění.
enum PermissionState: Equatable {
    case granted, partial, missing, notDetermined, unknown

    var title: String {
        switch self {
        case .granted: return L("Povoleno")
        case .partial: return L("Jen částečně")
        case .missing: return L("Chybí")
        case .notDetermined: return L("Nevyžádáno")
        case .unknown: return L("Zjišťuji…")
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
        case .fullDiskAccess: return s.hudFocus
        case .calendar: return s.liveCalendar || s.tabCalendar
        case .camera: return s.mirrorButton
        case .bluetooth: return s.hudHeadphones
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
        next[.fullDiskAccess] = FullDiskAccess.isGranted ? .granted : .missing
        next[.calendar] = Self.calendarState()
        next[.camera] = Self.cameraState()
        next[.bluetooth] = Self.bluetoothState()
        if next != states { states = next }
    }

    /// Jde oprávnění vyžádat systémovým dialogem?
    func canPrompt(_ kind: PermissionKind) -> Bool {
        switch kind {
        case .accessibility: return state(kind) != .granted
        case .fullDiskAccess: return false
        case .calendar, .camera, .bluetooth: return state(kind) == .notDetermined
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
            return L("Povolen je jen zápis – NotchMax potřebuje plný přístup ke kalendářům.")
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
                        Text(compact ? L("Oprávnění: %@", kind.title) : kind.title)
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
                            GlassPill(title: L("Povolit"), symbol: "hand.raised.fill",
                                      tint: settings.accent.color.opacity(0.35)) {
                                center.request(kind)
                            }
                            .fixedSize()
                        }
                        GlassPill(title: L("Otevřít Nastavení"), symbol: "arrow.up.forward.app") {
                            kind.openSystemSettings()
                        }
                        .fixedSize()
                        if (kind == .fullDiskAccess || kind == .accessibility) && state != .granted {
                            GlassPill(title: L("Ukázat ve Finderu"), symbol: "folder") {
                                center.revealAppInFinder()
                            }
                            .fixedSize()
                        }
                        if compact {
                            GlassPill(title: L("Všechna oprávnění"), symbol: "lock.shield") {
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
            SettingsCard(header: L("Přehled")) {
                ForEach(Array(PermissionKind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 { SettingsDivider() }
                    PermissionRow(kind: kind)
                }
            }

            SettingsCard(header: L("Když oprávnění nefunguje")) {
                SettingsNote(symbol: "exclamationmark.triangle",
                             text: L("Přepínač v Nastavení systému je zapnutý, ale tady svítí „Chybí“? Vyber NotchMax v seznamu, odeber ho tlačítkem (−) a přidej znovu tlačítkem (+) – nebo ho do seznamu přetáhni z Finderu. Potom NotchMax restartuj."))
                SettingsDivider()
                SettingsNote(symbol: "signature",
                             text: L("Po každé aktualizaci nepodepsaného sestavení může macOS udělená oprávnění zapomenout, protože aplikaci pozná podle podpisu. Trvalé řešení je stabilní podpisový certifikát – viz README a skript scripts/create-signing-cert.sh."))
                SettingsDivider()
                SettingsActionRow(title: L("Akce")) {
                    GlassPill(title: L("Zkontrolovat znovu"), symbol: "arrow.clockwise") {
                        FullDiskAccess.invalidateCache()
                        center.refresh()
                    }
                    .fixedSize()
                    GlassPill(title: L("Ukázat NotchMax ve Finderu"), symbol: "folder") {
                        center.revealAppInFinder()
                    }
                    .fixedSize()
                    GlassPill(title: L("Ukončit NotchMax"), symbol: "power") {
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
            SettingsCard(header: L("HUD hlasitosti a jasu")) {
                SettingsToggleRow(title: L("Nahradit systémové HUD"),
                                  subtitle: L("Hlasitost, jas displeje a podsvícení klávesnice se zobrazí v notchi místo uprostřed obrazovky."),
                                  isOn: $settings.hudReplaceSystem)
                if settings.hudReplaceSystem {
                    SettingsDivider()
                    PermissionRow(kind: .accessibility, compact: true)
                }
            }

            SettingsCard(header: L("Animace v notchi")) {
                SettingsToggleRow(title: L("Přehrávání médií"),
                                  subtitle: L("Krátká animace při play, pauze, další a předchozí skladbě."),
                                  isOn: $settings.hudMedia)
                SettingsDivider()
                SettingsToggleRow(title: L("AirPods a sluchátka"),
                                  subtitle: L("Animace při připojení s ukazatelem baterie."),
                                  isOn: $settings.hudHeadphones)
                if settings.hudHeadphones && center.state(.bluetooth) == .missing {
                    SettingsDivider()
                    PermissionRow(kind: .bluetooth, compact: true)
                }
                SettingsDivider()
                SettingsRow(title: L("Vyzkoušet animaci sluchátek"),
                            subtitle: L("Ukáže HUD právě připojených sluchátek (model, barva, baterie), nebo ukázku, když žádná připojená nejsou.")) {
                    GlassPill(title: L("Vyzkoušet animaci"), symbol: "airpodspro") {
                        HeadphonesMonitor.shared.showTestAnimation()
                    }
                    .fixedSize()
                }
                SettingsDivider()
                SettingsToggleRow(title: L("Soustředění"),
                                  subtitle: L("Ukáže v notchi, když zapneš nebo vypneš režim soustředění."),
                                  isOn: $settings.hudFocus)
                if settings.hudFocus && !focusMonitor.canRead {
                    SettingsDivider()
                    PermissionRow(kind: .fullDiskAccess, compact: true)
                }
                SettingsDivider()
                SettingsToggleRow(title: L("Claude agenti – hotovo / čeká na tebe"),
                                  subtitle: L("Upozorní v notchi, když agent dokončí práci nebo potřebuje tvoje rozhodnutí."),
                                  isOn: $settings.hudClaude)
            }
        }
    }
}
