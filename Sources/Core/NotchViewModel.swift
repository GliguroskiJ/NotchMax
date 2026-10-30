import SwiftUI

enum NotchTab: String, CaseIterable, Identifiable {
    case home, calendar, shelf, tools

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .calendar: return "calendar"
        case .shelf: return "tray.full.fill"
        case .tools: return "timer"
        }
    }

    var title: String {
        switch self {
        case .home: return "Přehled"
        case .calendar: return "Kalendář"
        case .shelf: return "Odkladiště"
        case .tools: return "Nástroje"
        }
    }
}

@MainActor
final class NotchViewModel: ObservableObject {
    enum Banner: Equatable { case charging }

    @Published var isOpen = false
    @Published var tab: NotchTab = .home
    @Published var geometry: NotchGeometry
    @Published var banner: Banner?
    /// Průběh „sweepu“ kolem notche při zapojení nabíječky (0…1).
    @Published var chargeSweep: CGFloat = 0
    @Published var chargeOpacity: Double = 0

    private var chargeTask: Task<Void, Never>?

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    /// Animace po zapojení nabíječky: notch se rozšíří, kolem něj proběhne zelený sweep.
    func runChargeAnimation() {
        guard !isOpen else { return }
        chargeTask?.cancel()
        chargeSweep = 0
        chargeOpacity = 1
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { banner = .charging }
        chargeTask = Task { [weak self] in
            // Nech SwiftUI nejdřív vykreslit výchozí stav (0), jinak se sweep po prvním spuštění nepřehraje.
            await Task.yield()
            try? await Task.sleep(nanoseconds: 40_000_000)
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeInOut(duration: 1.3)) { self.chargeSweep = 1 }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) { self.banner = nil }
            withAnimation(.easeOut(duration: 0.7)) { self.chargeOpacity = 0 }
        }
    }
}
