import SwiftUI

/// Druh AirPods / sluchátek (určuje ikonu a animaci).
enum HeadphoneModel: String, Equatable {
    case airpods, airpods3, airpodsPro, airpodsMax, beats, generic

    var symbol: String {
        switch self {
        case .airpods: return "airpods"
        case .airpods3: return "airpods.gen3"
        case .airpodsPro: return "airpodspro"
        case .airpodsMax: return "airpodsmax"
        case .beats: return "beats.headphones"
        case .generic: return "headphones"
        }
    }
}

/// Barva sluchátek (pokud ji jde zjistit) – HUD podle ní obarví ikonu.
enum HeadphoneColor: String, Equatable, CaseIterable {
    case white, black, spaceGray, silver, skyBlue, pink, green, midnight, starlight, orange, purple, blue, red

    var color: Color {
        switch self {
        case .white: return Color(white: 0.96)
        case .black: return Color(white: 0.18)
        case .spaceGray: return Color(red: 0.42, green: 0.43, blue: 0.45)
        case .silver: return Color(red: 0.85, green: 0.86, blue: 0.87)
        case .skyBlue: return Color(red: 0.62, green: 0.75, blue: 0.85)
        case .pink: return Color(red: 0.95, green: 0.74, blue: 0.75)
        case .green: return Color(red: 0.70, green: 0.78, blue: 0.64)
        case .midnight: return Color(red: 0.20, green: 0.23, blue: 0.29)
        case .starlight: return Color(red: 0.93, green: 0.89, blue: 0.82)
        case .orange: return Color(red: 0.95, green: 0.62, blue: 0.38)
        case .purple: return Color(red: 0.72, green: 0.64, blue: 0.85)
        case .blue: return Color(red: 0.36, green: 0.53, blue: 0.80)
        case .red: return Color(red: 0.80, green: 0.22, blue: 0.24)
        }
    }
}

enum MediaAction: Equatable { case play, pause, next, previous }

/// Jedna krátká „HUD“ událost zobrazená v notchi (místo systémových OSD a oznámení).
enum HUDEvent: Equatable {
    /// level 0…1
    case volume(level: Double, muted: Bool)
    case brightness(level: Double)
    case keyboardBrightness(level: Double)
    case media(action: MediaAction, title: String?, artist: String?)
    /// Baterie 0…100, nil = neznámo
    case headphones(name: String, model: HeadphoneModel, color: HeadphoneColor?, left: Int?, right: Int?, caseLevel: Int?, connected: Bool)
    case focus(name: String, symbol: String, enabled: Bool)
    case claude(project: String, needsAttention: Bool, message: String?)

    /// Jak dlouho zůstane HUD vidět (s).
    var duration: TimeInterval {
        switch self {
        case .volume, .brightness, .keyboardBrightness: return 1.6
        case .media: return 1.4
        case .headphones: return 4.0
        case .focus: return 2.4
        case .claude: return 4.0
        }
    }

    /// Události stejné „rodiny“ se přepisují bez zavírání (např. opakované stisky hlasitosti).
    var family: String {
        switch self {
        case .volume: return "volume"
        case .brightness: return "brightness"
        case .keyboardBrightness: return "keyboard"
        case .media: return "media"
        case .headphones: return "headphones"
        case .focus: return "focus"
        case .claude: return "claude"
        }
    }
}

/// Centrální fronta HUD událostí. Producenti volají `HUDCenter.shared.show(_:)`,
/// NotchRootView zobrazuje `current`.
@MainActor
final class HUDCenter: ObservableObject {
    static let shared = HUDCenter()

    @Published private(set) var current: HUDEvent?
    /// Mění se při každém zobrazení (i stejné rodiny) – pro restart animací.
    @Published private(set) var revision: Int = 0

    private var queue: [HUDEvent] = []
    private var hideTask: Task<Void, Never>?

    private init() {}

    func show(_ event: HUDEvent) {
        // Rychlé ovládací HUD (hlasitost, jas, média) přeskočí frontu a hned nahradí aktuální.
        let immediate: Bool
        switch event {
        case .volume, .brightness, .keyboardBrightness, .media: immediate = true
        default: immediate = false
        }
        if let cur = current, cur.family != event.family, !immediate {
            if queue.count < 6 { queue.append(event) }
            return
        }
        // Rychlé HUD přerušilo oznámení / sluchátka / Clauda → vrátit ho do fronty, ať se neztratí.
        if immediate, let cur = current, cur.family != event.family {
            switch cur {
            case .headphones, .claude, .focus: queue.insert(cur, at: 0)
            default: break
            }
        }
        present(event)
    }

    func dismiss() {
        hideTask?.cancel()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { current = nil }
        if !queue.isEmpty {
            let next = queue.removeFirst()
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                self?.present(next)
            }
        }
    }

    private func present(_ event: HUDEvent) {
        hideTask?.cancel()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.8)) {
            current = event
            revision &+= 1
        }
        let d = event.duration
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(d * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }
}
