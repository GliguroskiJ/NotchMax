import Foundation

/// Překlady textů okna Nastavení (čeština → angličtina) pro `L(…)`.
enum L10nSettings {
    static let table: [String: String] = [
        "Obecné":
            "General",
        "Vzhled":
            "Appearance",
        "Notch":
            "Notch",
        "Panel":
            "Panel",
        "Časovač a soustředění":
            "Timer & Focus",
        "Kalendář":
            "Calendar",
        "Oprávnění":
            "Permissions",
        "Agenti":
            "Agents",
        "Aktualizace":
            "Updates",
        "Funkce":
            "Features",
        "Aplikace":
            "App",
        "Verze %@":
            "Version %@",
        "Chybějící oprávnění":
            "Missing permissions",
        "Jazyk":
            "Language",
        "Jazyk / Language":
            "Language / Jazyk",
        "Jazyk rozhraní NotchMaxu.":
            "NotchMax interface language.",
        "Spuštění":
            "Startup",
        "Spouštět při přihlášení":
            "Launch at login",
        "NotchMax se spustí automaticky po přihlášení k Macu.":
            "NotchMax starts automatically when you log in to your Mac.",
        "Globální zkratka ⌥⌘N":
            "Global shortcut ⌥⌘N",
        "Otevře a zavře notch z klávesnice.":
            "Opens and closes the notch from the keyboard.",
        "Chování":
            "Behavior",
        "Prodleva při najetí":
            "Hover delay",
        "Jak dlouho musí myš zůstat na notchi, než se rozbalí.":
            "How long the pointer has to stay on the notch before it expands.",
        "Zobrazit na":
            "Show on",
        "Na kterém displeji se notch zobrazí.":
            "Which display the notch appears on.",
        "Ukončit NotchMax":
            "Quit NotchMax",
        "Odstín akcentní barvy":
            "Accent color hue",
        "%ld stupňů":
            "%ld degrees",
        "Bílá":
            "White",
        "Odstín %ld°":
            "Hue %ld°",
        "Barva zvýraznění":
            "Accent color",
        "Neutrální bílé zvýraznění místo barevného odstínu.":
            "Neutral white accent instead of a colored hue.",
        "Poloha a velikost notche":
            "Notch position and size",
        "Posun nahoru / dolů":
            "Move up / down",
        "Doladění, aby tvar přesně seděl na fyzický notch. Kladná hodnota posune nahoru.":
            "Fine-tune so the shape fits the physical notch exactly. A positive value moves it up.",
        "Přesah pod notch":
            "Overhang below the notch",
        "O kolik tvar vyčnívá pod fyzický notch. 0 = přesně na jeho výšku.":
            "How far the shape extends below the physical notch. 0 = exactly its height.",
        "Výchozí hodnoty":
            "Defaults",
        "Posun %+.0f px, přesah %.0f px.":
            "Offset %+.0f px, overhang %.0f px.",
        "Obnovit":
            "Reset",
        "Animace nabíjení":
            "Charging animation",
        "Animace při zapojení nabíječky":
            "Animate when the charger is connected",
        "Levá strana":
            "Left side",
        "Pravá strana":
            "Right side",
        "Zúží (+) nebo rozšíří (−) obrys nabíjení. Po změně se animace přehraje.":
            "Narrows (+) or widens (−) the charging outline. The animation plays after each change.",
        "Vyzkoušet animaci":
            "Test animation",
        "Přehrát":
            "Play",
        "Aplikace je záměrně jen v tmavém režimu, aby splynula s černým notchem. Skleněné prvky vypadají stejně, ať je panel aktivní, nebo ne.":
            "The app is intentionally dark-only so it blends in with the black notch. Glass elements look the same whether the panel is active or not.",
        "Vrátit na výchozí hodnotu":
            "Reset to default",
        "Živé aktivity vedle notche":
            "Live activities next to the notch",
        "Hudba":
            "Music",
        "Obal alba a ekvalizér.":
            "Album art and equalizer.",
        "Časovač":
            "Timer",
        "Blížící se schůzka":
            "Upcoming meeting",
        "Zobrazí se 10 minut předem.":
            "Shown 10 minutes in advance.",
        "Claude agenti":
            "Claude agents",
        "Stav běžících Claude agentů.":
            "Status of running Claude agents.",
        "Dvě aktivity naráz se řeší automaticky: když běží víc aktivit (třeba hudba a časovač), notch ukáže dvě naposledy spuštěné – jednu vlevo a jednu vpravo od notche. Nic dalšího nastavovat nemusíš.":
            "Two activities at once are handled automatically: when several are running (say music and a timer), the notch shows the two most recently started – one on the left and one on the right of the notch. Nothing else to set up.",
        "Záložky v rozbaleném notchi":
            "Tabs in the expanded notch",
        "Odkladiště souborů":
            "File shelf",
        "Nástroje":
            "Tools",
        "Časovač a další rychlé nástroje.":
            "Timer and other quick tools.",
        "Systém":
            "System",
        "Statistiky CPU, paměti a sítě.":
            "CPU, memory and network stats.",
        "Přehled Claude agentů.":
            "Overview of Claude agents.",
        "V notchi se vejde nejvýš 5 záložek včetně Domů – víc by se schovalo za fyzický notch.":
            "The notch fits at most 5 tabs including Home – more would hide behind the physical notch.",
        "Zrcátko":
            "Mirror",
        "Tlačítko kamery v notchi":
            "Camera button in the notch",
        "Rychlý náhled z kamery – zkontroluj se před hovorem.":
            "Quick camera preview – check yourself before a call.",
        "Odkladiště":
            "Shelf",
        "Mazat odkladiště po":
            "Clear shelf after",
        "Soubory v odkladišti se po této době samy odeberou.":
            "Files on the shelf are removed automatically after this time.",
        "1 hodině":
            "1 hour",
        "24 hodinách":
            "24 hours",
        "7 dnech":
            "7 days",
        "Nikdy":
            "Never",
        "Verze":
            "Version",
        "Sestavení %@":
            "Build %@",
        "Zkontrolovat":
            "Check",
        "Poslední kontrola":
            "Last check",
        "Automatické kontroly":
            "Automatic checks",
        "Kontrolovat automaticky":
            "Check automatically",
        "Kontrola probíhá při startu, po probuzení Macu a jednou denně. Aktualizace se nainstaluje vždy až po tvém potvrzení.":
            "Checks run at launch, after your Mac wakes and once a day. An update is only installed after you confirm it.",
        "Po aktualizaci":
            "After updating",
        "Zkontroluj oprávnění":
            "Check permissions",
        "Po aktualizaci nepodepsaného sestavení může macOS zapomenout udělená oprávnění.":
            "After updating an unsigned build, macOS may forget the permissions you granted.",
        "Zobrazit oprávnění":
            "Show permissions",
        "Zatím neproběhla":
            "Not yet",
        "Zpřístupnění":
            "Accessibility",
        "Plný přístup k disku":
            "Full Disk Access",
        "Kamera":
            "Camera",
        "Bluetooth":
            "Bluetooth",
        "HUD hlasitosti a jasu v notchi a přepínání Nerušit s časovačem.":
            "Volume and brightness HUD in the notch and toggling Do Not Disturb with the timer.",
        "Rozpoznání zapnutí a vypnutí režimu Soustředění (animace v notchi). Nedá se vyžádat dialogem – v seznamu zapni NotchMax, a když tam není, přidej ho tlačítkem (+).":
            "Detecting when a Focus mode is turned on or off (notch animation). It can't be requested with a dialog – turn on NotchMax in the list, and if it isn't there, add it with the (+) button.",
        "Nadcházející události v notchi a v záložce Kalendář.":
            "Upcoming events in the notch and in the Calendar tab.",
        "Zrcátko – náhled z kamery v notchi.":
            "Mirror – camera preview in the notch.",
        "Animace při připojení AirPods a sluchátek.":
            "Animation when AirPods and headphones connect.",
        "Povoleno":
            "Allowed",
        "Jen částečně":
            "Partial only",
        "Chybí":
            "Missing",
        "Nevyžádáno":
            "Not requested",
        "Zjišťuji…":
            "Checking…",
        "Povolen je jen zápis – NotchMax potřebuje plný přístup ke kalendářům.":
            "Only write access is allowed – NotchMax needs full access to calendars.",
        "Oprávnění: %@":
            "Permission: %@",
        "Povolit":
            "Allow",
        "Otevřít Nastavení":
            "Open Settings",
        "Ukázat ve Finderu":
            "Show in Finder",
        "Všechna oprávnění":
            "All permissions",
        "Přehled":
            "Overview",
        "Když oprávnění nefunguje":
            "When a permission doesn't work",
        "Přepínač v Nastavení systému je zapnutý, ale tady svítí „Chybí“? Vyber NotchMax v seznamu, odeber ho tlačítkem (−) a přidej znovu tlačítkem (+) – nebo ho do seznamu přetáhni z Finderu. Potom NotchMax restartuj.":
            "The switch in System Settings is on, but this still says “Missing”? Select NotchMax in the list, remove it with the (−) button and add it again with (+) – or drag it into the list from Finder. Then restart NotchMax.",
        "Po každé aktualizaci nepodepsaného sestavení může macOS udělená oprávnění zapomenout, protože aplikaci pozná podle podpisu. Trvalé řešení je stabilní podpisový certifikát – viz README a skript scripts/create-signing-cert.sh.":
            "After every update of an unsigned build, macOS may forget granted permissions because it identifies the app by its signature. The permanent fix is a stable signing certificate – see the README and scripts/create-signing-cert.sh.",
        "Akce":
            "Actions",
        "Zkontrolovat znovu":
            "Check again",
        "Ukázat NotchMax ve Finderu":
            "Show NotchMax in Finder",
        "HUD hlasitosti a jasu":
            "Volume and brightness HUD",
        "Nahradit systémové HUD":
            "Replace the system HUD",
        "Hlasitost, jas displeje a podsvícení klávesnice se zobrazí v notchi místo uprostřed obrazovky.":
            "Volume, display brightness and keyboard backlight are shown in the notch instead of the middle of the screen.",
        "Animace v notchi":
            "Notch animations",
        "Přehrávání médií":
            "Media playback",
        "Krátká animace při play, pauze, další a předchozí skladbě.":
            "A short animation on play, pause, next and previous track.",
        "AirPods a sluchátka":
            "AirPods and headphones",
        "Animace při připojení s ukazatelem baterie.":
            "Animation on connect with a battery indicator.",
        "Vyzkoušet animaci sluchátek":
            "Test the headphones animation",
        "Ukáže HUD právě připojených sluchátek (model, barva, baterie), nebo ukázku, když žádná připojená nejsou.":
            "Shows the HUD for the currently connected headphones (model, color, battery), or a demo if none are connected.",
        "Soustředění":
            "Focus",
        "Ukáže v notchi, když zapneš nebo vypneš režim soustředění.":
            "Shows in the notch when you turn a Focus mode on or off.",
        "Claude agenti – hotovo / čeká na tebe":
            "Claude agents – done / waiting for you",
        "Upozorní v notchi, když agent dokončí práci nebo potřebuje tvoje rozhodnutí.":
            "Alerts you in the notch when an agent finishes or needs your decision.",
        "Soustředění s časovačem":
            "Focus with the timer",
        "Zapnout Nerušit s časovačem":
            "Turn on Do Not Disturb with the timer",
        "Při spuštění focus časovače se zapne Nerušit, po skončení nebo zastavení se zase vypne.":
            "Starting the focus timer turns on Do Not Disturb; it turns off again when the timer ends or is stopped.",
        "NotchMax přepíná „Nerušit“ automaticky – nic dalšího nastavovat nemusíš. Pokud už bylo Nerušit zapnuté před spuštěním časovače, po skončení ho nechá zapnuté.":
            "NotchMax toggles “Do Not Disturb” automatically – nothing else to set up. If Do Not Disturb was already on before the timer started, it stays on afterwards.",
        "NotchMax na okamžik otevře v menu baru Soustředění (nebo Ovládací centrum), přepne „Nerušit“ a menu zase zavře. Bez oprávnění Zpřístupnění to nejde. Po aktualizaci nepodepsaného sestavení může být potřeba NotchMax v seznamu Zpřístupnění odebrat (−) a přidat znovu (+).":
            "NotchMax briefly opens Focus (or Control Center) in the menu bar, toggles “Do Not Disturb” and closes the menu again. This doesn't work without the Accessibility permission. After updating an unsigned build you may need to remove NotchMax from the Accessibility list (−) and add it again (+).",
        "Vyzkoušet":
            "Test",
        "Vyzkoušet Nerušit":
            "Test Do Not Disturb",
        "Diagnostika":
            "Diagnostics",
        "Diagnostický záznam":
            "Diagnostic log",
        "Uloží do souboru stav Soustředění, oprávnění a poslední pokusy o přepnutí Nerušit. Hodí se při hlášení chyby.":
            "Saves the Focus state, permissions and recent Do Not Disturb attempts to a file. Useful when reporting a bug.",
        "Zobrazit ve Finderu":
            "Show in Finder",
        "Uloženo: %@":
            "Saved: %@",
        "Diagnostiku se nepodařilo uložit.":
            "Couldn't save the diagnostics.",
        "Naposledy fungovalo: %@":
            "Last worked: %@",
        "Zapne Nerušit a po 3 s ho zase vypne.":
            "Turns on Do Not Disturb and turns it off again after 3 s.",
        "Zapínám Nerušit…":
            "Turning on Do Not Disturb…",
        "Nepodařilo se zapnout: %@":
            "Couldn't turn it on: %@",
        "neznámá chyba":
            "unknown error",
        "Nerušit už bylo zapnuté – funguje (%@).":
            "Do Not Disturb was already on – it works (%@).",
        "Nerušit zapnuto – vypnu za 3 s…":
            "Do Not Disturb on – turning off in 3 s…",
        "Vypínám Nerušit…":
            "Turning off Do Not Disturb…",
        "Funguje ✓ (%@)":
            "Works ✓ (%@)",
        "Zapnutí fungovalo, vypnutí ne: %@":
            "Turning on worked, turning off didn't: %@",
        "Zobrazení":
            "Display",
        "Záložka Agenti":
            "Agents tab",
        "Přehled relací Claude Code v rozbaleném notchi.":
            "Overview of Claude Code sessions in the expanded notch.",
        "Živá aktivita u notche":
            "Live activity by the notch",
        "Když Claude pracuje nebo čeká na tebe, ukáže se stav vedle notche.":
            "When Claude is working or waiting for you, the status is shown next to the notch.",
        "Hooky Claude Code":
            "Claude Code hooks",
        "Stav":
            "Status",
        "Nainstalováno – NotchMax ví přesně, kdy Claude pracuje, dokončí tah nebo čeká na povolení.":
            "Installed – NotchMax knows exactly when Claude is working, finishes a turn or is waiting for permission.",
        "Nenainstalováno – stav se odhaduje jen z transkriptů, takže „čeká na tebe“ se nepozná.":
            "Not installed – status is only estimated from transcripts, so “waiting for you” can't be detected.",
        "Aktivní":
            "Active",
        "Neaktivní":
            "Inactive",
        "Spravovat hooky":
            "Manage hooks",
        "Instalovat hooky":
            "Install hooks",
        "Upraví ~/.claude/settings.json (původní obsah zůstane, záloha v settings.json.notchmax-backup). Platí pro nově spuštěné relace.":
            "Edits ~/.claude/settings.json (existing content is kept, backup in settings.json.notchmax-backup). Applies to newly started sessions.",
        "Přeinstalovat":
            "Reinstall",
        "Odinstalovat":
            "Uninstall",
        "Hooky na události SessionStart, UserPromptSubmit, PreToolUse, Notification, Stop a SessionEnd jen připíšou řádek do ~/Library/Application Support/NotchMax/claude-events.jsonl (pomocí tr, date a printf, které jsou v každém macOS). Nic neblokují, nic nevypisují do konverzace a nikam se neposílají. Odinstalace odstraní jen položky označené „NotchMax“.":
            "Hooks on the SessionStart, UserPromptSubmit, PreToolUse, Notification, Stop and SessionEnd events just append a line to ~/Library/Application Support/NotchMax/claude-events.jsonl (using tr, date and printf, which every macOS has). They block nothing, print nothing into the conversation and send nothing anywhere. Uninstalling removes only entries marked “NotchMax”.",
        "Relace":
            "Sessions",
        "Nalezené relace":
            "Sessions found",
        "Za posledních 24 hodin: %ld · pracuje %ld · čeká %ld":
            "Last 24 hours: %ld · working %ld · waiting %ld",
        "Otevřít ~/.claude":
            "Open ~/.claude",
        "Vidět jsou jen relace Claude Code (CLI v terminálu, případně v IDE) na tomto Macu – čtou se z ~/.claude/projects. Konverzace v aplikaci Claude pro desktop ani chaty na claude.ai se lokálně neukládají, takže je NotchMax zobrazit nemůže.":
            "Only Claude Code sessions (CLI in the terminal, or in an IDE) on this Mac are visible – they're read from ~/.claude/projects. Conversations in the Claude desktop app and chats on claude.ai aren't stored locally, so NotchMax can't show them.",
        "Hooky jsou nainstalované. Projeví se v nově spuštěných relacích Claude Code (běžící relaci restartuj).":
            "Hooks are installed. They take effect in newly started Claude Code sessions (restart any running session).",
        "Hooky NotchMax byly odebrány, ostatní nastavení zůstalo beze změny.":
            "NotchMax hooks were removed; other settings were left unchanged.",
        "Kalendáře macOS":
            "macOS calendars",
        "Přístup ke kalendářům":
            "Calendar access",
        "Kalendáře z aplikace Kalendář – iCloud, Exchange i Google účet přidaný do macOS.":
            "Calendars from the Calendar app – iCloud, Exchange and Google accounts added to macOS.",
        "Povolit přístup":
            "Allow access",
        "Otevřít nastavení":
            "Open settings",
        "NotchMax má od macOS jen přístup pro přidávání událostí, takže je nemůže číst. V Nastavení systému → Soukromí a zabezpečení → Kalendáře změň u NotchMax přístup na „Plný přístup“.":
            "macOS only gave NotchMax access to add events, so it can't read them. In System Settings → Privacy & Security → Calendars, change NotchMax's access to “Full Access”.",
        "Přístup byl zamítnut. Povol ho v Nastavení systému → Soukromí a zabezpečení → Kalendáře.":
            "Access was denied. Allow it in System Settings → Privacy & Security → Calendars.",
        "Google účet":
            "Google account",
        "V Internetových účtech přidej Google a zapni u něj Kalendáře – objeví se tady.":
            "Add Google in Internet Accounts and turn on Calendars for it – they'll show up here.",
        "Přidat Google účet":
            "Add Google account",
        "Zobrazené kalendáře":
            "Shown calendars",
        "Zatím tu nejsou žádné kalendáře. Přidej účet v Internetových účtech nebo vytvoř kalendář v aplikaci Kalendář.":
            "There are no calendars yet. Add an account in Internet Accounts or create a calendar in the Calendar app.",
        "Jen zápis":
            "Write only",
        "Zamítnuto":
            "Denied",
        "Zatím nepovoleno":
            "Not allowed yet",
        "Azurová":
            "Cyan",
        "Mátová":
            "Mint",
        "Fialová":
            "Violet",
        "Oranžová":
            "Orange",
        "Automaticky":
            "Automatic",
        "Schůzka":
            "Meeting",
        "Baterie":
            "Battery",
        "Nic":
            "None",
        "Displej s notchem":
            "Display with notch",
        "Hlavní displej":
            "Main display",
        "Maximálně 5 záložek – jinak by se schovaly za notch. Nejdřív jinou vypni.":
            "At most 5 tabs – otherwise they'd hide behind the notch. Turn another one off first.",
        "Ovládací centrum (Zpřístupnění)":
            "Control Center (Accessibility)",
    ]
}
