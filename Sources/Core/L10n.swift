import Foundation

/// Jednoduchá lokalizace: zdrojové texty jsou česky, `L("…")` vrátí anglický překlad,
/// když je v nastavení zvolená angličtina. Překlady jsou rozdělené do tabulek podle oblasti
/// (každá tabulka je `[čeština: angličtina]`).
///
/// Pro texty s proměnnými použij formát: `L("Konec v %@", time)` nebo `L("%d min", 5)` –
/// klíč tabulky je pak šablona („Konec v %@“), překlad musí mít stejné zástupné znaky.
enum L10n {
    /// Všechny tabulky dohromady (sloučí se jednou, při prvním použití).
    static let table: [String: String] = {
        var all: [String: String] = [:]
        for part in [L10nNotch.table, L10nPanels.table, L10nSettings.table, L10nServices.table] {
            all.merge(part) { first, _ in first }
        }
        return all
    }()

    static var isEnglish: Bool {
        // Čteno z UserDefaults, ať funguje i mimo hlavní vlákno (AppSettings je @MainActor svět).
        UserDefaults.standard.string(forKey: "language") == AppLanguage.en.rawValue
    }

    static func translate(_ text: String) -> String {
        guard isEnglish else { return text }
        return table[text] ?? text
    }
}

/// Přeloží český text do zvoleného jazyka aplikace.
func L(_ text: String) -> String {
    L10n.translate(text)
}

/// Přeloží šablonu a dosadí argumenty (`%@`, `%d`, `%.0f` …).
func L(_ format: String, _ args: CVarArg...) -> String {
    String(format: L10n.translate(format), arguments: args)
}
