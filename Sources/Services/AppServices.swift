import SwiftUI

/// Společné služby aplikace (jedna instance na celý proces).
@MainActor
final class AppServices {
    static let shared = AppServices()

    let settings = AppSettings.shared
    let battery = BatteryMonitor()
    let media = MediaMonitor()
    let calendar = CalendarMonitor()
    let shelf = ShelfStore()
    let timer = FocusTimer()
    let updates = UpdateManager()

    /// Nastaví NotchWindowController při startu.
    var viewModel: NotchViewModel?

    private init() {}
}

extension View {
    /// Vloží všechny služby do prostředí view.
    @MainActor
    func withServices(_ s: AppServices = AppServices.shared) -> some View {
        self
            .environmentObject(s.settings)
            .environmentObject(s.battery)
            .environmentObject(s.media)
            .environmentObject(s.calendar)
            .environmentObject(s.shelf)
            .environmentObject(s.timer)
            .environmentObject(s.updates)
    }
}
