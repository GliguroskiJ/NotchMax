import SwiftUI

/// Akcentní barva aplikace: libovolný odstín ze spektra, nebo bílá.
/// Všechny views používají `settings.accent.color`.
struct NotchAccent: Equatable {
    /// Sytost a jas pro barevné odstíny – živé, ale ne neonové.
    static let saturation: Double = 0.72
    static let brightness: Double = 1.0

    let hue: Double
    let isWhite: Bool

    init(hue: Double, isWhite: Bool = false) {
        self.hue = min(max(hue, 0), 1)
        self.isWhite = isWhite
    }

    var color: Color {
        if isWhite { return .white }
        return Color(hue: hue, saturation: NotchAccent.saturation, brightness: NotchAccent.brightness)
    }

    /// Barva daného odstínu (bez ohledu na volbu bílé) – pro náhledy a posuvník.
    static func color(forHue hue: Double) -> Color {
        Color(hue: min(max(hue, 0), 1), saturation: saturation, brightness: brightness)
    }
}

/// Dřívější pevné akcentní barvy. Zůstává kvůli migraci uloženého nastavení
/// a jako rychlé předvolby u posuvníku odstínu.
enum AccentChoice: String, CaseIterable, Identifiable {
    case cyan, mint, violet, orange, white

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cyan: return "Azurová"
        case .mint: return "Mátová"
        case .violet: return "Fialová"
        case .orange: return "Oranžová"
        case .white: return "Bílá"
        }
    }

    /// Odstín (0…1), který nejlépe odpovídá původní barvě.
    var hue: Double {
        switch self {
        case .cyan: return 0.54
        case .mint: return 0.47
        case .violet: return 0.78
        case .orange: return 0.08
        case .white: return 0.54
        }
    }

    var accent: NotchAccent { NotchAccent(hue: hue, isWhite: self == .white) }

    var color: Color { accent.color }
}

/// Co se zobrazí na jedné straně notche, když je zapnutý režim dvou aktivit.
enum ActivitySlot: String, CaseIterable, Identifiable {
    case auto, music, timer, meeting, battery, claude, none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Automaticky"
        case .music: return "Hudba"
        case .timer: return "Časovač"
        case .meeting: return "Schůzka"
        case .battery: return "Baterie"
        case .claude: return "Claude agenti"
        case .none: return "Nic"
        }
    }

    var symbol: String {
        switch self {
        case .auto: return "wand.and.stars"
        case .music: return "music.note"
        case .timer: return "timer"
        case .meeting: return "calendar"
        case .battery: return "battery.75percent"
        case .claude: return "sparkles"
        case .none: return "minus.circle"
        }
    }
}

enum DisplayChoice: String, CaseIterable, Identifiable {
    case builtIn, primary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .builtIn: return "Displej s notchem"
        case .primary: return "Hlavní displej"
        }
    }
}

/// Nastavení uložená v UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var hoverDelay: Double { didSet { UserDefaults.standard.set(hoverDelay, forKey: "hoverDelay") } }
    /// Odstín akcentní barvy (0…1 přes celé spektrum).
    @Published var accentHue: Double { didSet { UserDefaults.standard.set(accentHue, forKey: "accentHue") } }
    /// Bílá akcentní barva (sytost 0) místo odstínu.
    @Published var accentWhite: Bool { didSet { UserDefaults.standard.set(accentWhite, forKey: "accentWhite") } }
    @Published var display: DisplayChoice { didSet { UserDefaults.standard.set(display.rawValue, forKey: "display") } }
    @Published var chargingAnimation: Bool { didSet { UserDefaults.standard.set(chargingAnimation, forKey: "chargingAnimation") } }
    @Published var liveBattery: Bool { didSet { UserDefaults.standard.set(liveBattery, forKey: "liveBattery") } }
    @Published var liveMusic: Bool { didSet { UserDefaults.standard.set(liveMusic, forKey: "liveMusic") } }
    @Published var liveCalendar: Bool { didSet { UserDefaults.standard.set(liveCalendar, forKey: "liveCalendar") } }
    @Published var liveTimer: Bool { didSet { UserDefaults.standard.set(liveTimer, forKey: "liveTimer") } }
    @Published var tabCalendar: Bool { didSet { UserDefaults.standard.set(tabCalendar, forKey: "tabCalendar") } }
    @Published var tabShelf: Bool { didSet { UserDefaults.standard.set(tabShelf, forKey: "tabShelf") } }
    @Published var tabTools: Bool { didSet { UserDefaults.standard.set(tabTools, forKey: "tabTools") } }
    @Published var tabSystem: Bool { didSet { UserDefaults.standard.set(tabSystem, forKey: "tabSystem") } }
    @Published var hotkeyEnabled: Bool { didSet { UserDefaults.standard.set(hotkeyEnabled, forKey: "hotkeyEnabled") } }
    /// Posun notche v bodech: kladná hodnota = nahoru, záporná = dolů.
    @Published var notchOffsetY: Double { didSet { UserDefaults.standard.set(notchOffsetY, forKey: "notchOffsetY") } }
    /// O kolik tvar přesahuje pod fyzický notch (0 = přesně na výšku notche).
    @Published var notchOverhang: Double { didSet { UserDefaults.standard.set(notchOverhang, forKey: "notchOverhang") } }
    @Published var tabAgents: Bool { didSet { UserDefaults.standard.set(tabAgents, forKey: "tabAgents") } }
    @Published var liveClaude: Bool { didSet { UserDefaults.standard.set(liveClaude, forKey: "liveClaude") } }
    /// Dvě nezávislé aktivity (vlevo a vpravo od notche) místo jedné rozdělené.
    @Published var dualActivities: Bool { didSet { UserDefaults.standard.set(dualActivities, forKey: "dualActivities") } }
    @Published var leftActivity: ActivitySlot { didSet { UserDefaults.standard.set(leftActivity.rawValue, forKey: "leftActivity") } }
    @Published var rightActivity: ActivitySlot { didSet { UserDefaults.standard.set(rightActivity.rawValue, forKey: "rightActivity") } }
    /// Zúžení (kladné) / rozšíření (záporné) obrysu nabíjení na levé a pravé straně, v bodech.
    @Published var chargeInsetLeft: Double { didSet { UserDefaults.standard.set(chargeInsetLeft, forKey: "chargeInsetLeft") } }
    @Published var chargeInsetRight: Double { didSet { UserDefaults.standard.set(chargeInsetRight, forKey: "chargeInsetRight") } }
    /// Při spuštění časovače zapnout Soustředění (přes zkratky), po skončení vypnout.
    @Published var focusWithTimer: Bool { didSet { UserDefaults.standard.set(focusWithTimer, forKey: "focusWithTimer") } }
    @Published var focusOnShortcut: String { didSet { UserDefaults.standard.set(focusOnShortcut, forKey: "focusOnShortcut") } }
    @Published var focusOffShortcut: String { didSet { UserDefaults.standard.set(focusOffShortcut, forKey: "focusOffShortcut") } }
    /// Identifikátory kalendářů (EKCalendar.calendarIdentifier), které se nemají zobrazovat.
    @Published var hiddenCalendarIDs: [String] { didSet { UserDefaults.standard.set(hiddenCalendarIDs, forKey: "hiddenCalendarIDs") } }
    // HUD v notchi (hlasitost, jas, média, sluchátka, soustředění, oznámení) a zrcátko.
    @Published var hudReplaceSystem: Bool { didSet { UserDefaults.standard.set(hudReplaceSystem, forKey: "hudReplaceSystem") } }
    @Published var hudMedia: Bool { didSet { UserDefaults.standard.set(hudMedia, forKey: "hudMedia") } }
    @Published var hudHeadphones: Bool { didSet { UserDefaults.standard.set(hudHeadphones, forKey: "hudHeadphones") } }
    @Published var hudFocus: Bool { didSet { UserDefaults.standard.set(hudFocus, forKey: "hudFocus") } }
    @Published var hudNotifications: Bool { didSet { UserDefaults.standard.set(hudNotifications, forKey: "hudNotifications") } }
    @Published var hudClaude: Bool { didSet { UserDefaults.standard.set(hudClaude, forKey: "hudClaude") } }
    @Published var mirrorButton: Bool { didSet { UserDefaults.standard.set(mirrorButton, forKey: "mirrorButton") } }
    /// 0 = nikdy nemazat
    @Published var shelfTTLHours: Int { didSet { UserDefaults.standard.set(shelfTTLHours, forKey: "shelfTTLHours") } }

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "hoverDelay": 0.15,
            "display": DisplayChoice.builtIn.rawValue,
            "chargingAnimation": true,
            "liveBattery": true,
            "liveMusic": true,
            "liveCalendar": true,
            "liveTimer": true,
            "tabCalendar": true,
            "tabShelf": true,
            "tabTools": true,
            "tabSystem": true,
            "notchOffsetY": AppSettings.defaultNotchOffsetY,
            "notchOverhang": AppSettings.defaultNotchOverhang,
            "hotkeyEnabled": true,
            "shelfTTLHours": 24,
            "tabAgents": false,
            "liveClaude": false,
            "dualActivities": false,
            "leftActivity": ActivitySlot.music.rawValue,
            "rightActivity": ActivitySlot.timer.rawValue,
            "chargeInsetLeft": AppSettings.defaultChargeInset,
            "chargeInsetRight": AppSettings.defaultChargeInset,
            "focusWithTimer": false,
            "hudReplaceSystem": true,
            "hudMedia": true,
            "hudHeadphones": true,
            "hudFocus": true,
            "hudNotifications": false,
            "hudClaude": false,
            "mirrorButton": true,

            "focusOnShortcut": "NotchMax Focus On",
            "focusOffShortcut": "NotchMax Focus Off"
        ])
        hoverDelay = d.double(forKey: "hoverDelay")
        if let storedHue = d.object(forKey: "accentHue") as? Double {
            accentHue = min(max(storedHue, 0), 1)
            accentWhite = d.bool(forKey: "accentWhite")
        } else {
            // Migrace z dřívější pevné volby (`accent` = cyan/mint/violet/orange/white).
            let legacy = AccentChoice(rawValue: d.string(forKey: "accent") ?? "") ?? .cyan
            accentHue = legacy.hue
            accentWhite = legacy == .white
            d.set(legacy.hue, forKey: "accentHue")
            d.set(legacy == .white, forKey: "accentWhite")
        }
        display = DisplayChoice(rawValue: d.string(forKey: "display") ?? "") ?? .builtIn
        chargingAnimation = d.bool(forKey: "chargingAnimation")
        liveBattery = d.bool(forKey: "liveBattery")
        liveMusic = d.bool(forKey: "liveMusic")
        liveCalendar = d.bool(forKey: "liveCalendar")
        liveTimer = d.bool(forKey: "liveTimer")
        tabCalendar = d.bool(forKey: "tabCalendar")
        tabShelf = d.bool(forKey: "tabShelf")
        tabTools = d.bool(forKey: "tabTools")
        tabSystem = d.bool(forKey: "tabSystem")
        notchOffsetY = d.double(forKey: "notchOffsetY")
        notchOverhang = d.double(forKey: "notchOverhang")
        hotkeyEnabled = d.bool(forKey: "hotkeyEnabled")
        shelfTTLHours = d.integer(forKey: "shelfTTLHours")
        tabAgents = d.bool(forKey: "tabAgents")
        liveClaude = d.bool(forKey: "liveClaude")
        dualActivities = d.bool(forKey: "dualActivities")
        leftActivity = ActivitySlot(rawValue: d.string(forKey: "leftActivity") ?? "") ?? .music
        rightActivity = ActivitySlot(rawValue: d.string(forKey: "rightActivity") ?? "") ?? .timer
        chargeInsetLeft = d.double(forKey: "chargeInsetLeft")
        chargeInsetRight = d.double(forKey: "chargeInsetRight")
        focusWithTimer = d.bool(forKey: "focusWithTimer")
        focusOnShortcut = d.string(forKey: "focusOnShortcut") ?? "NotchMax Focus On"
        focusOffShortcut = d.string(forKey: "focusOffShortcut") ?? "NotchMax Focus Off"
        hudReplaceSystem = d.bool(forKey: "hudReplaceSystem")
        hudMedia = d.bool(forKey: "hudMedia")
        hudHeadphones = d.bool(forKey: "hudHeadphones")
        hudFocus = d.bool(forKey: "hudFocus")
        hudNotifications = d.bool(forKey: "hudNotifications")
        hudClaude = d.bool(forKey: "hudClaude")
        mirrorButton = d.bool(forKey: "mirrorButton")
        hiddenCalendarIDs = d.stringArray(forKey: "hiddenCalendarIDs") ?? []
    }

    /// Aktuální akcentní barva (`settings.accent.color`).
    var accent: NotchAccent { NotchAccent(hue: accentHue, isWhite: accentWhite) }

    // MARK: Výchozí hodnoty polohy notche a obrysu nabíjení

    static let defaultNotchOffsetY: Double = 0
    static let defaultNotchOverhang: Double = 1
    static let defaultChargeInset: Double = 0

    /// Vrátí posun a přesah notche na výchozí hodnoty.
    func resetNotchGeometry() {
        notchOffsetY = AppSettings.defaultNotchOffsetY
        notchOverhang = AppSettings.defaultNotchOverhang
    }

    /// Vrátí zúžení obrysu nabíjení na výchozí hodnoty.
    func resetChargeInsets() {
        chargeInsetLeft = AppSettings.defaultChargeInset
        chargeInsetRight = AppSettings.defaultChargeInset
    }

    var visibleTabs: [NotchTab] {
        var tabs: [NotchTab] = [.home]
        if tabCalendar { tabs.append(.calendar) }
        if tabShelf { tabs.append(.shelf) }
        if tabTools { tabs.append(.tools) }
        if tabSystem { tabs.append(.system) }
        if tabAgents { tabs.append(.agents) }
        // Víc než 5 záložek by se v hlavičce schovalo za fyzický notch.
        return Array(tabs.prefix(AppSettings.maxVisibleTabs))
    }

    /// Maximální počet záložek v hlavičce rozbaleného notche (včetně Domů).
    static let maxVisibleTabs = 5

    /// Text vysvětlující, proč nejde zapnout další záložku.
    static let tabLimitNote = "Maximálně 5 záložek – jinak by se schovaly za notch. Nejdřív jinou vypni."

    /// Počet zapnutých volitelných záložek (bez Domů).
    var enabledOptionalTabCount: Int {
        [tabCalendar, tabShelf, tabTools, tabSystem, tabAgents].filter { $0 }.count
    }

    /// Jestli jde zapnout další volitelnou záložku (Domů je vždy, takže max. 4 volitelné).
    var canEnableMoreTabs: Bool {
        enabledOptionalTabCount < AppSettings.maxVisibleTabs - 1
    }
}
