import Foundation

/// Překlady textů notche (záložky, hlavička rozbaleného panelu, HUD). `[čeština: angličtina]`.
enum L10nNotch {
    static let table: [String: String] = [
        // Záložky
        "Přehled": "Overview",
        "Kalendář": "Calendar",
        "Odkladiště": "Shelf",
        "Nástroje": "Tools",
        "Systém": "System",
        "Agenti": "Agents",

        // Hlavička rozbaleného panelu
        "Skrýt zrcátko": "Hide mirror",
        "Zrcátko": "Mirror",
        "Nastavení": "Settings",

        // HUD – sluchátka
        "Sluchátka": "Headphones",
        "Připojeno": "Connected",
        "Odpojeno": "Disconnected",
        "P": "R",
        "Pouzdro": "Case",

        // HUD – Claude
        "Čeká na tebe": "Needs you",
        "Hotovo": "Done",
    ]
}
