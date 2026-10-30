import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable {
    case home, calendar, shelf, tools, system

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .calendar: return "calendar"
        case .shelf: return "tray.full.fill"
        case .tools: return "wrench.and.screwdriver.fill"
        case .system: return "gauge.with.dots.needle.67percent"
        }
    }

    var title: String {
        switch self {
        case .home: return "Přehled"
        case .calendar: return "Kalendář"
        case .shelf: return "Odkladiště"
        case .tools: return "Nástroje"
        case .system: return "Systém"
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
    @Published var banner: Banner?
    /// Začátek animace nabíjení (nil = neběží). Animaci kreslí TimelineView podle času,
    /// takže nezávisí na SwiftUI přechodech a přehraje se při každém zapojení.
    @Published var chargeStart: Date?

    private var chargeTask: Task<Void, Never>?

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    /// Animace po zapojení nabíječky: notch se lehce nafoukne a kolem jeho obrysu proběhne zelený sweep.
    func runChargeAnimation() {
        guard !isOpen else { return }
        chargeTask?.cancel()
        chargeStart = Date()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { banner = .charging }
        chargeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_600_000_000)
            guard !Task.isCancelled, let self else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { self.banner = nil }
            self.chargeStart = nil
        }
    }
}
