import Foundation

/// Překlady obsahu záložek rozbaleného panelu (Přehled, Kalendář, Odkladiště, Systém,
/// Nástroje, Agenti, Zrcátko) a sdílených komponent. Klíč = český text, hodnota = angličtina.
enum L10nPanels {
    static let table: [String: String] = [
        // Přehled – přehrávač
        "Nic nehraje": "Nothing playing",
        "Spusť Apple Music nebo Spotify": "Start Apple Music or Spotify",
        "Předchozí": "Previous",
        "Pozastavit": "Pause",
        "Přehrát": "Play",
        "Další": "Next",

        // Přehled – schůzky a baterie
        "Žádné další schůzky": "No more meetings",
        "Kalendář": "Calendar",
        "Připojit kalendář": "Connect calendar",
        "Právě probíhá": "Happening now",
        "Další schůzka": "Next meeting",
        "Připojit se": "Join",
        "Celý den: %@": "All day: %@",
        "do %@": "until %@",
        "Napájení ze sítě": "On AC power",
        "Nabíjí se · plná za %d h %d min": "Charging · full in %d h %d min",
        "Nabíjí se": "Charging",
        "Zapojeno": "Plugged in",
        "Na baterii": "On battery",

        // Kalendář
        "Dnes": "Today",
        "Zítra": "Tomorrow",
        "Celý den": "All day",
        "Volno": "All clear",
        "Žádné události dnes ani zítra": "No events today or tomorrow",
        "Přístup ke kalendářům macOS je zamítnutý. Povol ho v Nastavení.":
            "Access to macOS calendars is denied. Allow it in Settings.",
        "Připoj kalendáře macOS – iCloud, Google i další účty.":
            "Connect macOS calendars – iCloud, Google and other accounts.",
        "Připojit": "Join",

        // Odkladiště
        "Přetáhni sem soubory": "Drop files here",
        "Odsud je pak přetáhneš jinam nebo pošleš přes AirDrop":
            "Then drag them elsewhere or send them via AirDrop",
        "Poslat vše přes AirDrop": "Send all via AirDrop",
        "Vyprázdnit odkladiště": "Clear shelf",

        // Systém
        "Procesor": "CPU",
        "Paměť": "Memory",
        "Síť": "Network",
        "Disk": "Disk",
        "Teplota CPU": "CPU temperature",
        "Ventilátory": "Fans",
        "Energie": "Power",
        "Doba běhu": "Uptime",
        "z %@ GB": "of %@ GB",
        "volno z %@ GB": "free of %@ GB",
        "Nedostupné": "Unavailable",
        "Bez ventilátoru": "Fanless",
        "Pasivní chlazení": "Passive cooling",
        "od spuštění systému": "since system start",
        "V pohodě": "Cool",
        "Zahřátý": "Warm",
        "Horký": "Hot",
        "Velmi horký": "Very hot",
        "nabíjí": "charging",
        "adaptér": "adapter",
        "z baterie": "on battery",
        "Zdraví %d %%": "Health %d %%",
        "Baterie": "Battery",

        // Nástroje – časovač a Soustředění
        "Focus časovač": "Focus timer",
        "Konec v %@": "Ends at %@",
        "Zastavit": "Stop",
        "Zastavit časovač": "Stop timer",
        "Spustit": "Start",
        "Spustit časovač na %d min": "Start timer for %d min",
        "zbývá": "left",
        "připraveno": "ready",
        "Soustředění": "Focus",
        "Povolit": "Allow",
        "Povolit NotchMaxu Zpřístupnění, aby mohl přepínat Nerušit":
            "Allow NotchMax Accessibility access so it can toggle Do Not Disturb",
        "Nenechat usnout": "Keep awake",
        "Displej zůstane zapnutý.": "Display stays on.",
        "Vypnuto.": "Off.",
        "Vypnuto": "Off",
        "Potřebuje Zpřístupnění": "Needs Accessibility",
        "Chyba – viz časovač": "Error – see timer",
        "Nerušit zapnuto s časovačem": "Do Not Disturb on with timer",
        "Připraveno – zapne Nerušit": "Ready – turns on Do Not Disturb",
        "%d minut": "%d minutes",

        // Agenti
        "pracuje": "working",
        "čeká": "waiting",
        "nečinné": "idle",
        "Obnovit": "Refresh",
        "Otevřít v Terminálu": "Open in Terminal",
        "Otevřít %@ v Terminálu": "Open %@ in Terminal",
        "Zobrazit ve Finderu": "Show in Finder",
        "Kopírovat příkaz pro obnovení": "Copy resume command",
        "Spusť Claude Code v terminálu": "Start Claude Code in a terminal",
        "Relace Claude Code z posledních 24 hodin se zobrazí tady.":
            "Claude Code sessions from the last 24 hours will appear here.",
        "Relace z posledních 24 hodin se zobrazí tady. Pro přesnější stav nainstaluj hooky v Nastavení → Agenti.":
            "Sessions from the last 24 hours will appear here. For more accurate status, install the hooks in Settings → Agents.",
        "Pracuje": "Working",
        "Čeká na tebe": "Waiting for you",
        "Nečinný": "Idle",
        "právě teď": "just now",
        "před %d min": "%d min ago",
        "před %d h": "%d h ago",
        "před %d d": "%d d ago",

        // Zrcátko
        "Žádná kamera": "No camera",
        "Připoj kameru nebo iPhone (Kamera Continuity).": "Connect a camera or an iPhone (Continuity Camera).",
        "Kameru se nepodařilo spustit": "Couldn't start the camera",
        "Zkusit znovu": "Try again",
        "Žádám o přístup ke kameře…": "Requesting camera access…",
        "Přístup ke kameře je zakázán": "Camera access is denied",
        "Povol NotchMaxu kameru v Nastavení systému → Soukromí a zabezpečení → Kamera.":
            "Allow NotchMax to use the camera in System Settings → Privacy & Security → Camera.",
        "Otevřít nastavení": "Open Settings",
        "Kamera": "Camera",
        "Přepnout kameru": "Switch camera",
        "Vypnout zrcadlení": "Turn off mirroring",
        "Zapnout zrcadlení": "Turn on mirroring",
        "Světlo": "Light",
        "Kruhové světlo kolem náhledu": "Ring light around the preview"
    ]
}
