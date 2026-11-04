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
    /// Pevná velikost průhledného okna (obsahuje i prostor pro stín a animaci nabíjení).
    static let panelSize = CGSize(width: 640, height: 300)
    /// Velikost rozbaleného notche. Šířka = levý sloupec hlavičky (lišta záložek) + mezera pro notch
    /// + pravý sloupec (tlačítka) + boční odsazení; obsah pod hlavičkou je široký `contentWidth` (534 pt).
    /// Výška: headerTop 10 + controlHeight 28 + headerGap 10 + obsah 188 + margin 14 = 250.
    static let openSize = CGSize(width: 600, height: 250)

    // MARK: Zavřený notch a live activity
    /// Horní (vnější) zaoblení zavřeného tvaru – o tolik tvar na každé straně přesahuje fyzický notch.
    static let closedTopRadius: CGFloat = 6
    /// Spodní zaoblení zavřeného tvaru. Souzní s odsazením obsahu: ikona 18 pt má ve výšce ~34 pt
    /// svisle ~8 pt volna a obal alba poloměr 5, takže 8 + 5 = 13.
    static let closedBottomRadius: CGFloat = 13
    /// Odsazení obsahu live activity od vnějšího (zaobleného) okraje.
    /// Malé, aby obsah vlevo přiléhal k levému a vpravo k pravému vnějšímu okraji.
    static let compactOuterPadding: CGFloat = 7
    /// Odsazení obsahu live activity od fyzického notche.
    static let compactInnerPadding: CGFloat = 4
    /// Velikost ikony / obalu alba v live activity.
    static let compactIcon: CGFloat = 18
    /// Mezera mezi ikonou a detailem uvnitř jednoho widgetu.
    static let compactGap: CGFloat = 6
    /// Minimální šířka oblasti pro najetí myší vedle notche (na každou stranu).
    static let hoverSideMin: CGFloat = 52

    // MARK: Rozestupy (jednotná škála 8 / 12 / 14)
    static let spacingS: CGFloat = 8
    static let spacingM: CGFloat = 12
    static let spacingL: CGFloat = 14
    /// Jednotný okraj obsahu rozbaleného panelu (po stranách, dole i mezi kartami).
    static let margin: CGFloat = 14
    /// Odsazení hlavičky (záložky, tlačítka) od horního okraje panelu.
    static let headerTop: CGFloat = 10
    /// Mezera mezi hlavičkou a kartami – stejná jako `headerTop`.
    static let headerGap: CGFloat = 10
    /// Mezera pro fyzický notch v hlavičce navíc k jeho šířce (dohromady za obě strany).
    static let headerNotchMargin: CGFloat = 12

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
    /// Šířka obsahové oblasti rozbaleného panelu (600 - 2 × 33 = 534 pt).
    static let contentWidth: CGFloat = openSize.width - 2 * sideInset
    /// Šířka pravého sloupce karet (Přehled, Nástroje).
    static let columnWidth: CGFloat = 170
}
