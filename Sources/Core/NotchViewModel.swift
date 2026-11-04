import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable {
    case home, calendar, shelf, tools, system, agents

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .calendar: return "calendar"
        case .shelf: return "tray.full.fill"
        case .tools: return "wrench.and.screwdriver.fill"
        case .system: return "gauge.with.dots.needle.67percent"
        case .agents: return "sparkles"
        }
    }

    var title: String {
        switch self {
        case .home: return "Přehled"
        case .calendar: return "Kalendář"
        case .shelf: return "Odkladiště"
        case .tools: return "Nástroje"
        case .system: return "Systém"
        case .agents: return "Agenti"
        }
    }
}

@MainActor
final class NotchViewModel: ObservableObject {
    enum Banner: Equatable { case charging }

    @Published var isOpen = false
    /// Dokud je true (např. při psaní poznámky), se panel nezavře po odjetí myši.
    @Published var holdOpen = false
    @Published var tab: NotchTab = .home
    @Published var geometry: NotchGeometry
    /// Během animace nabíjení se skryjí live activity a tvar má přesně velikost notche.
    @Published var banner: Banner?
    /// Začátek animace nabíjení (nil = neběží). Animaci kreslí TimelineView podle času,
    /// takže nezávisí na SwiftUI přechodech a přehraje se při každém zapojení.
    @Published var chargeStart: Date?
    /// Rozbalený panel ukazuje zrcátko kamery místo obsahu záložky.
    @Published var showMirror = false

    /// Aktuální šířka live activity vlevo / vpravo od notche (bez horního zaoblení).
    /// Zapisuje ji NotchRootView, čte NotchWindowController pro oblast najetí myší.
    /// Záměrně není @Published, aby zápis nevyvolával překreslení.
    var closedSideWidths: (left: CGFloat, right: CGFloat) = (0, 0)

    private var chargeTask: Task<Void, Never>?

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    /// Animace po zapojení nabíječky: obrysem notche proběhnou zelené pulzy až k úrovni nabití.
    func runChargeAnimation() {
        guard !isOpen else { return }
        chargeTask?.cancel()
        chargeStart = Date()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { banner = .charging }
        chargeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((ChargeSweep.duration + 0.1) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.chargeStart = nil
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { self.banner = nil }
        }
    }
}
