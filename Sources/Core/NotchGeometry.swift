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
    static let openSize = CGSize(width: 580, height: 252)
    /// Šířka jedné strany „live activity“ vedle notche.
    static let sideActivity: CGFloat = 46
    /// O kolik tvar vyčnívá pod fyzický notch, aby byl obrys a glow vidět.
    static let lip: CGFloat = 5

    // MARK: Rozestupy (jednotná škála 8 / 12 / 14)
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 12
    static let spacingL: CGFloat = 14
    /// Jednotný okraj obsahu rozbaleného panelu (po stranách, dole i mezi kartami).
    static let margin: CGFloat = 14

    // MARK: Poloměry
    /// Poloměry rozbaleného tvaru (horní rohy tvar rozšiřují, obsah se o ně musí odsadit).
    static let openTopRadius: CGFloat = 19
    static let openBottomRadius: CGFloat = 34
    /// Karty jsou soustředné se spodním rohem tvaru: 34 - 14 = 20.
    static let cardRadius: CGFloat = openBottomRadius - margin
    /// Prvky uvnitř karty s odsazením 10 (obal alba, řádky seznamu): 20 - 10.
    static let nestedRadius: CGFloat = cardRadius - 10

    // MARK: Rozměry
    /// Výška ovládacích prvků v hlavičce (kapsle záložek, baterie, ozubené kolo).
    static let controlHeight: CGFloat = 28
    /// Boční odsazení obsahu od okraje okna (horní poloměr tvaru + okraj).
    static let sideInset: CGFloat = openTopRadius + margin
    /// Šířka pravého sloupce karet (Přehled, Nástroje).
    static let columnWidth: CGFloat = 170
}
