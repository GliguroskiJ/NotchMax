import SwiftUI

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

    var color: Color {
        switch self {
        case .cyan: return .cyan
        case .mint: return .mint
        case .violet: return .purple
        case .orange: return .orange
        case .white: return .white
        }
    }
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
    @Published var accent: AccentChoice { didSet { UserDefaults.standard.set(accent.rawValue, forKey: "accent") } }
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
    /// 0 = nikdy nemazat
    @Published var shelfTTLHours: Int { didSet { UserDefaults.standard.set(shelfTTLHours, forKey: "shelfTTLHours") } }

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "hoverDelay": 0.15,
            "accent": AccentChoice.cyan.rawValue,
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
            "notchOffsetY": 2.0,
            "notchOverhang": 2.0,
            "hotkeyEnabled": true,
            "shelfTTLHours": 24,
            "tabAgents": true,
            "liveClaude": true,
            "dualActivities": false,
            "leftActivity": ActivitySlot.music.rawValue,
            "rightActivity": ActivitySlot.timer.rawValue,
            "chargeInsetLeft": 0.0,
            "chargeInsetRight": 0.0,
            "focusWithTimer": false,
            "focusOnShortcut": "NotchMax Focus On",
            "focusOffShortcut": "NotchMax Focus Off"
        ])
        hoverDelay = d.double(forKey: "hoverDelay")
        accent = AccentChoice(rawValue: d.string(forKey: "accent") ?? "") ?? .cyan
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
        hiddenCalendarIDs = d.stringArray(forKey: "hiddenCalendarIDs") ?? []
    }

    var visibleTabs: [NotchTab] {
        var tabs: [NotchTab] = [.home]
        if tabCalendar { tabs.append(.calendar) }
        if tabShelf { tabs.append(.shelf) }
        if tabTools { tabs.append(.tools) }
        if tabSystem { tabs.append(.system) }
        if tabAgents { tabs.append(.agents) }
        return tabs
    }
}
