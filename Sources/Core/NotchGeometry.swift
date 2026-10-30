import AppKit

/// Rozměry notche na daném displeji. Bez notche (starší Mac, externí monitor)
/// se použije „virtuální notch“ o výšce menu baru.
struct NotchGeometry {
    let screen: NSScreen
    let hasNotch: Bool
    let notchSize: CGSize

    init(screen: NSScreen) {
        self.screen = screen
        let inset = screen.safeAreaInsets.top
        if inset > 0 {
            hasNotch = true
            let left = screen.auxiliaryTopLeftArea?.width ?? 0
            let right = screen.auxiliaryTopRightArea?.width ?? 0
            let width = screen.frame.width - left - right
            notchSize = CGSize(width: max(width, 150), height: inset)
        } else {
            hasNotch = false
            let menuBar = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
            notchSize = CGSize(width: 190, height: menuBar)
        }
    }
}

enum NotchLayout {
    /// Pevná velikost průhledného okna (obsahuje i prostor pro glow a stín).
    static let panelSize = CGSize(width: 720, height: 320)
    /// Velikost rozbaleného notche.
    static let openSize = CGSize(width: 580, height: 224)
    /// Šířka jedné strany „live activity“ vedle notche.
    static let sideActivity: CGFloat = 46
}
