import Foundation

/// Překlady textů ze služeb (Services/*): stavové a chybové zprávy, názvy režimů
/// Soustředění, stavy relací Claude, kalendáře, sluchátka, kamera.
/// Klíč = český zdrojový text (u šablon včetně zástupných znaků), hodnota = angličtina.
/// Pozor: klíče se v literálu nesmí opakovat (jinak pád za běhu).
enum L10nServices {
    static let table: [String: String] = [
        // MARK: Soustředění – přepínání (FocusController)
        "Klávesová zkratka Nerušit": "Do Not Disturb keyboard shortcut",
        "Ovládací centrum (Zpřístupnění)": "Control Center (Accessibility)",
        "Chybí oprávnění Zpřístupnění": "Accessibility permission is missing",
        "Klávesová zkratka Nerušit neodpovídá": "The Do Not Disturb shortcut is not responding",
        "Nerušit se po stisku nepřepnulo": "Do Not Disturb did not switch after the press",
        "Ovládací centrum neodpovídá": "Control Center is not responding",
        "Služba Nerušit neodpovídá": "The Do Not Disturb service is not responding",
        "Systém požadavek na Nerušit ignoroval": "The system ignored the Do Not Disturb request",
        "Povol NotchMaxu Zpřístupnění, aby mohl přepínat Nerušit": "Allow NotchMax Accessibility access so it can switch Do Not Disturb",
        "Nerušit se nepodařilo přepnout": "Could not switch Do Not Disturb",
        "Stav Soustředění nejde přečíst (chybí plný přístup k disku)": "Focus state can't be read (Full Disk Access is missing)",
        "Klávesovou zkratku pro Nerušit se nepodařilo nastavit": "Could not set up the Do Not Disturb keyboard shortcut",
        "Klávesovou zkratku nejde odeslat": "The keyboard shortcut can't be sent",
        "Systém na klávesovou zkratku Nerušit nereagoval": "The system did not respond to the Do Not Disturb shortcut",
        "Ovládací centrum neběží": "Control Center is not running",
        "Menu bar Ovládacího centra není dostupný": "The Control Center menu bar is not available",
        "Menu bar Ovládacího centra je prázdný": "The Control Center menu bar is empty",
        "Přepínač Nerušit nebyl nalezen": "The Do Not Disturb toggle was not found",
        "V menu baru chybí Ovládací centrum": "Control Center is missing from the menu bar",
        "Menu se nepodařilo otevřít": "Could not open the menu",
        "Přepínač Nerušit nejde stisknout": "The Do Not Disturb toggle can't be pressed",
        "DoNotDisturb.framework není dostupný": "DoNotDisturb.framework is not available",
        "Nepodporovaná verze DoNotDisturb.framework": "Unsupported version of DoNotDisturb.framework",
        "Nepodařilo se vytvořit požadavek na Nerušit": "Could not create the Do Not Disturb request",
        "Systém odmítl Nerušit (%ld)": "The system refused Do Not Disturb (%ld)",
        "Systém odmítl Nerušit": "The system refused Do Not Disturb",
        "Systém odmítl vypnutí Nerušit (%ld)": "The system refused to turn off Do Not Disturb (%ld)",

        // MARK: Soustředění – názvy režimů (FocusModeMonitor)
        "Soustředění": "Focus",
        "Nerušit": "Do Not Disturb",
        "Omezit vyrušování": "Reduce Interruptions",
        "Práce": "Work",
        "Osobní": "Personal",
        "Spánek": "Sleep",
        "Řízení": "Driving",

        // MARK: Focus časovač
        "Nerušit se nepodařilo zapnout": "Could not turn on Do Not Disturb",
        "Nerušit se nepodařilo vypnout": "Could not turn off Do Not Disturb",

        // MARK: Sluchátka
        "Sluchátka": "Headphones",

        // MARK: Claude
        "Pracuje": "Working",
        "Čeká na tebe": "Waiting for you",
        "Nečinný": "Idle",
        "Soubor ~/.claude/settings.json není platný JSON objekt. Oprav ho ručně, NotchMax ho nepřepíše.":
            "~/.claude/settings.json is not a valid JSON object. Fix it manually – NotchMax won't overwrite it.",
        "Nepodařilo se upravit ~/.claude/settings.json: %@": "Could not update ~/.claude/settings.json: %@",

        // MARK: Kalendář
        "Bez názvu": "Untitled",
        "Ostatní": "Other",
        "Na tomto Macu": "On My Mac",
        "Narozeniny": "Birthdays",
        "Odebírané kalendáře": "Subscribed calendars",
        "Účet": "Account",
        "Místní": "Local",
        "Odběr": "Subscription",
        "Kontakty": "Contacts",

        // MARK: Kamera
        "Tuto kameru teď nelze použít.": "This camera can't be used right now.",
    ]
}
