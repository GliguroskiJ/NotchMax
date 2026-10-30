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

enum GlowStyle: String, CaseIterable, Identifiable {
    case off, pulse, aurora, minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "Vypnuto"
        case .pulse: return "Pulzující"
        case .aurora: return "Aurora (rotující)"
        case .minimal: return "Jemná linka"
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
    @Published var glowStyle: GlowStyle { didSet { UserDefaults.standard.set(glowStyle.rawValue, forKey: "glowStyle") } }
    @Published var display: DisplayChoice { didSet { UserDefaults.standard.set(display.rawValue, forKey: "display") } }
    @Published var chargingAnimation: Bool { didSet { UserDefaults.standard.set(chargingAnimation, forKey: "chargingAnimation") } }
    @Published var liveBattery: Bool { didSet { UserDefaults.standard.set(liveBattery, forKey: "liveBattery") } }
    @Published var liveMusic: Bool { didSet { UserDefaults.standard.set(liveMusic, forKey: "liveMusic") } }
    @Published var liveCalendar: Bool { didSet { UserDefaults.standard.set(liveCalendar, forKey: "liveCalendar") } }
    @Published var liveTimer: Bool { didSet { UserDefaults.standard.set(liveTimer, forKey: "liveTimer") } }
    @Published var tabCalendar: Bool { didSet { UserDefaults.standard.set(tabCalendar, forKey: "tabCalendar") } }
    @Published var tabShelf: Bool { didSet { UserDefaults.standard.set(tabShelf, forKey: "tabShelf") } }
    @Published var tabTools: Bool { didSet { UserDefaults.standard.set(tabTools, forKey: "tabTools") } }
    /// 0 = nikdy nemazat
    @Published var shelfTTLHours: Int { didSet { UserDefaults.standard.set(shelfTTLHours, forKey: "shelfTTLHours") } }

    private init() {
        let d = UserDefaults.standard
        d.register(defaults: [
            "hoverDelay": 0.15,
            "accent": AccentChoice.cyan.rawValue,
            "glowStyle": GlowStyle.pulse.rawValue,
            "display": DisplayChoice.builtIn.rawValue,
            "chargingAnimation": true,
            "liveBattery": true,
            "liveMusic": true,
            "liveCalendar": true,
            "liveTimer": true,
            "tabCalendar": true,
            "tabShelf": true,
            "tabTools": true,
            "shelfTTLHours": 24
        ])
        hoverDelay = d.double(forKey: "hoverDelay")
        accent = AccentChoice(rawValue: d.string(forKey: "accent") ?? "") ?? .cyan
        glowStyle = GlowStyle(rawValue: d.string(forKey: "glowStyle") ?? "") ?? .pulse
        display = DisplayChoice(rawValue: d.string(forKey: "display") ?? "") ?? .builtIn
        chargingAnimation = d.bool(forKey: "chargingAnimation")
        liveBattery = d.bool(forKey: "liveBattery")
        liveMusic = d.bool(forKey: "liveMusic")
        liveCalendar = d.bool(forKey: "liveCalendar")
        liveTimer = d.bool(forKey: "liveTimer")
        tabCalendar = d.bool(forKey: "tabCalendar")
        tabShelf = d.bool(forKey: "tabShelf")
        tabTools = d.bool(forKey: "tabTools")
        shelfTTLHours = d.integer(forKey: "shelfTTLHours")
    }

    var visibleTabs: [NotchTab] {
        var tabs: [NotchTab] = [.home]
        if tabCalendar { tabs.append(.calendar) }
        if tabShelf { tabs.append(.shelf) }
        if tabTools { tabs.append(.tools) }
        return tabs
    }
}
