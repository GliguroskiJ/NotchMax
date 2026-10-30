# NotchMax: research 2 (návrhy dalších funkcí)

Stav k 30. 10. 2026. Navazuje na `docs/SPEC.md`. Platí omezení projektu: macOS 14+, bez sandboxu, bez Apple Developer účtu (bez notarizace), žádná soukromá nebo neudržovaná API.

## 1. Co ukázal průzkum konkurence

Upozornění na kvalitu zdrojů: většina je marketingová (blogy autorů konkurenčních aplikací, affiliate srovnání, App Store a Product Hunt popisy). Reddit a GitHub issues se přes dostupné nástroje nepodařilo přečíst (GitHub `robots_disallowed`, Reddit se ve vyhledávání neobjevil). "Co uživatelé chtějí" je proto odvozeno hlavně z roadmap projektů, feature listů a z toho, co je v recenzích opakovaně zmiňováno jako chybějící. Ber to jako orientační.

| Aplikace | Stav / co nabízí | Co chybí nebo se kritizuje |
|---|---|---|
| NotchNook | produktivita: drag and drop, AirDrop, quick actions, widgety (kamera, kalendář, poznámky); ~$24 jednou nebo ~$3/měs. | podle srovnání bez clipboardu, kalendáře a focus timeru (údaje z affiliate blogů); tvrzení o výpadku v 09/2026 se nepodařilo potvrdit |
| Alcove | animace, mini-widgety, notifikace v notchi, jednorázová platba, 72h trial | žádná práce se soubory; podle recenzí spíš styl než praktičnost |
| Boring.Notch (GPL-3.0) | hudba + vizualizér, kalendář, shelf s AirDrop, náhrada HUD, zrcadlo; roadmapa: Reminders, baterie, Bluetooth live activity, počasí, lock screen widgety, extension systém, notifikace "zvažováno" | nepodepsaný build (Gatekeeper), pomalejší vývoj; k hudbě z prohlížečů používá MediaRemote Adapter |
| Atoll (GPL-3.0) | live activities (hudba, Focus, záznam obrazovky, indikátory soukromí, stahování beta), lock screen widgety (časovač, nabíjení, Bluetooth, počasí), CPU/GPU/RAM/síť/disk, clipboard historie, color picker, gesta | vyžaduje Accessibility, Camera, Calendar, Screen Recording, Music |
| NotchDrop (MIT) | shelf + AirDrop, automatické mazání po dni | jen shelf |
| Notchly ($15, bez notarizace) | 13 modulů: clipboard (60 položek), teleprompter, to-do, session manager, kamera, příkazy | zahlcení, ruční obejití Gatekeeperu |
| Droppy | notch + shelf + floating basket + clipboard, OCR, konverze | nejsilnější komerční konkurent; jediná zjištěná stížnost je "junk drawer" (příliš nástrojů), řešeno přepínáním záložek |
| Lyric Fever, Lyricly, Lyrimuse | synchronizované lyrics v menu baru / notchi / plovoucím okně; zdroje Spotify, LRCLIB, NetEase; překlad přes Apple on-device API | Lyric Fever potřebuje macOS 15+ |

Opakující se témata: (1) zahlcenost, proto modulárnost a vypínání záložek; (2) lehkost (CPU/baterie); (3) minimum oprávnění; (4) clipboard, system stats, počasí a lyrics se objevují u většiny aplikací, takže jsou "očekávaný standard"; (5) přehrávání z prohlížečů je bolest všech, ale řeší se soukromým MediaRemote (od macOS 15.4 nefunkční přímo z aplikace, obchází se přes `/usr/bin/perl`), což pro NotchMax nepřichází v úvahu.

## 2. Návrhy funkcí

Legenda: pracnost S (do ~1 dne), M (2-4 dny), L (týden a víc). Priorita 1-5 = hodnota pro uživatele vs. pracnost (5 nejlepší). Sloupec Izolace: **ANO** = jeden nový soubor služby + jedno view, bez nového oprávnění, do cizích souborů jen registrace (pár řádků v `AppServices`, `ToolsView`/`NotchTab`, `AppSettings`).

| # | Funkce | Popis | Technicky (veřejná API) | Oprávnění | Pracnost | Riziko | Prior. | Izolace |
|---|---|---|---|---|---|---|---|---|
| 1 | Systémové statistiky | CPU, RAM, síť, disk jako mini grafy v záložce Nástroje | `host_processor_info` / `host_statistics64` (CPU, RAM), `getifaddrs` (bajty na rozhraní), `URLResourceValues.volumeAvailableCapacityForImportantUsage` (disk); vzorkování 1x/s jen při otevřeném notchi | žádné | S | nízké; Mach API jsou stabilní, ale dokumentace je řídká | 5 | **ANO** |
| 2 | Rychlé poznámky | Textové poznámky a checklist přímo v notchi, ukládání do souboru | SwiftUI `TextEditor`, JSON v `Application Support` (`FileManager`), autosave přes `Task` debounce | žádné | S | nízké | 5 | **ANO** |
| 3 | Počasí | Aktuální teplota, ikona a 3denní výhled | Open-Meteo `api.open-meteo.com/v1/forecast` + `geocoding-api.open-meteo.com/v1/search` (město zadané ručně, bez klíče); `URLSession` | žádné (síť; bez CoreLocation) | S | střední: free tier je jen pro nekomerční použití, vyžaduje CC-BY atribuci, do 10 000 volání/den; cache 30 min a kontrola licence, pokud by se NotchMax někdy prodával | 4 | **ANO** |
| 4 | Globální zkratka pro otevření notche | Klávesová zkratka rozbalí/zavře notch | Carbon `RegisterEventHotKey` + `InstallEventHandler` (nevyžaduje Accessibility; nemá deklarovanou deprecaci, v dokumentaci jsem stránku nenačetl, ověřeno jen z článku) | žádné | S | střední: nefunguje, když aktivní aplikace klávesu pohltí (např. terminál ve VS Code); `NSEvent.addGlobalMonitor` pro klávesy by vyžadoval Input Monitoring | 5 | skoro: soubor `HotKey.swift` + 1 řádek volání `NotchViewModel` |
| 5 | Indikátor mikrofonu a kamery | Pilulka v notchi, když mikrofon nebo kamera běží (ať ji používá kdokoli) | CoreAudio `kAudioDevicePropertyDeviceIsRunningSomewhere` (+ `AudioObjectAddPropertyListener`); CoreMediaIO `kCMIODevicePropertyDeviceIsRunningSomewhere` (macOS 10.12+, ověřeno v Apple docs) | žádné (jen stav zařízení, ne obsah) | S | střední: jméno aplikace veřejně zjistit nejde (to je ve SPEC jako "Strážce", potřebovalo by privátní věci nebo Endpoint Security); proto jen "běží / neběží" | 4 | **ANO** (jako samostatná pilulka) |
| 6 | Color picker s historií | Kapátko na barvy z obrazovky, kopírování HEX/RGB/HSL, posledních 10 barev | `NSColorSampler().show { }` (AppKit, macOS 10.15+, ověřeno); `NSPasteboard.general.setString` (zápis bez alertu) | žádné (dle dokumentace nic nepožaduje; ověř na stroji) | S | nízké | 3 | **ANO** |
| 7 | Spouštěč Zkratek (Shortcuts) | Mřížka oblíbených Zkratek, jedním klikem se spustí | `Process` s `/usr/bin/shortcuts list` a `shortcuts run "<název>"` (dokumentované CLI, ověřeno u Apple Support; nevhodné pro zkratky s dialogy) | žádné | S | nízké; výstup `list` je prostý text po řádcích | 4 | **ANO** |
| 8 | Časovač času po klientech | Start/stop podle klienta, součty za měsíc, export CSV (pro Fakturoid/fakturaci OSVČ) | vlastní JSON + `Timer`/`Date`, export `FileManager` + `NSSavePanel`; napojení na `FocusTimer` volitelné | žádné | M | nízké | 4 | **ANO** (samostatný modul, volitelně čte `FocusTimer`) |
| 9 | Připomínka pauzy podle skutečné aktivity | Po X minutách bez delší přestávky pulz glow a nabídka protažení | `CGEventSource.secondsSinceLastEventType(.combinedSessionState, kCGAnyInputEventType)` (macOS 10.4+, ověřeno; čtení doby nečinnosti nevyžaduje Accessibility) | žádné | S | nízké | 4 | **ANO** |
| 10 | Clipboard historie | Posledních 50-100 textů, URL a obrázků, hledání, vložení jedním klikem | polling `NSPasteboard.general.changeCount` (např. 0,5 s), čtení až při změně; od macOS 15.4 `NSPasteboard.detect*` a `accessBehavior` (macOS 15.4+, ověřeno); ukládání do souboru | formálně žádné, ale **riziko systémového alertu**: od macOS 15.4 je alert na programatické čtení pasteboardu ve vývojářském náhledu; zda je na macOS 26/27 vynucen pro třetí strany, se mi nepodařilo ověřit | M | vysoké pro UX: možný dialog "Povolit vložení z jiných aplikací"; ošetřit `accessBehavior`, ignorovat `org.nspasteboard.ConcealedType` (hesla) | 4 | ne (citlivé na systém) |
| 11 | Synchronizované lyrics | Řádek textu k právě hrající skladbě v notchi | LRCLIB `GET /api/get?track_name=&artist_name=&duration=` (bez klíče, `syncedLyrics` v LRC formátu, ~90 req/min s User-Agentem), pozice přehrávání z AppleScriptu Music/Spotify (`player position`) | žádné nové (Apple Events už se používají) | M | střední: LRCLIB je komunitní (pokrytí a přesnost kolísá), nutný User-Agent a cache; zasahuje `MediaMonitor` (pozice) | 4 | ne |
| 12 | Chytré akce při tažení souboru | Zmenšit obrázek, smazat EXIF, OCR do schránky, sloučit PDF | ImageIO (`CGImageSource`/`CGImageDestination`), Vision `VNRecognizeTextRequest` (macOS 10.15+, ověřeno, není deprecated), PDFKit `PDFDocument` | žádné | M | nízké; rozšiřuje `ShelfStore`/`ShelfView` | 4 | ne (zasahuje shelf) |
| 13 | Kontextové režimy | Layout notche podle aplikace v popředí (schůzka = Připojit + mute, IDE = timer) | `NSWorkspace.didActivateApplicationNotification`, `frontmostApplication.bundleIdentifier`; pravidla v nastavení | žádné | M | nízké; zasahuje `NotchRootView` | 3 | ne |
| 14 | Skrytí notche při sdílení obrazovky | Panel se nezobrazí ve sdíleném záznamu | `NSWindow.sharingType = .none` (macOS 10.5+, ověřeno) | žádné | S | **střední**: od macOS 15 ScreenCaptureKit toto nastavení u části záznamů ignoruje (z paměti, neověřeno), proto nesliboval bych 100% ochranu | 2 | skoro (1 řádek v `NotchPanel`) |
| 15 | Externí live aktivity | Skripty a Zkratky posílají do notche stav (např. "build hotov") | URL scheme `notchmax://activity?...` (`NSAppleEventManager` / `onOpenURL`), případně `DistributedNotificationCenter` | žádné | M | nízké; je třeba hlídat spam a zneužití (zobrazit jen text a ikonu) | 3 | ne |
| 16 | Zrcadlo (kamera) | Náhled kamery v notchi pro rychlou kontrolu před hovorem | `AVCaptureSession` + `AVCaptureVideoPreviewLayer` (NSViewRepresentable), `NSCameraUsageDescription` | **Kamera (nové)** | S | nízké; kamera se zapíná jen při otevřeném náhledu | 3 | ne (nové oprávnění) |
| 17 | Baterie Bluetooth zařízení | AirPods, myš, klávesnice s procenty | `system_profiler SPBluetoothDataType -json` přes `Process` (veřejný nástroj, položky `device_batteryLevel*`); alternativně IORegistry `AppleDeviceManagementHIDEventService` (`BatteryPercent`) | žádné | M | střední: formát JSON není garantovaný, parsovat defenzivně; `system_profiler` trvá ~1 s, volat řídce | 3 | ano, ale křehké |
| 18 | Hlasitost: live aktivita | Při změně hlasitosti krátce ukáže proužek v notchi | CoreAudio `AudioObjectAddPropertyListener` na `kAudioHardwarePropertyDefaultOutputDevice` a `kAudioDevicePropertyVolumeScalar` / `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` | žádné pro pozorování; **potlačení systémového HUD vyžaduje CGEventTap na media klávesy = Accessibility** | M | vysoké pro "náhradu HUD": bez Accessibility se objeví systémový HUD i náš. **Jas**: veřejné API pro vestavěný displej na Apple Silicon není (`DisplayServices*` je privátní, dle Hammerspoon issue 2668), proto jas vynechat | 2 | pozorování ANO, náhrada HUD ne |
| 19 | Náhled posledního screenshotu | Po pořízení screenshotu miniatura s akcemi (kopírovat, sdílet, smazat) | `NSMetadataQuery` s `kMDItemIsScreenCapture`, cílová složka z `defaults read com.apple.screencapture location` | **Přístup ke složce (Plocha/Dokumenty = TCC prompt)** | M | střední | 3 | ne |
| 20 | Kurzy ČNB a světové hodiny | Denní kurz EUR/USD a čas v dalších pásmech | `https://www.cnb.cz/cs/financni-trhy/devizovy-trh/kurzy-devizoveho-trhu/kurzy-devizoveho-trhu/denni_kurz.txt` (text oddělený `|`, desetinná čárka, ověřeno, 30 měn; podmínky užití tam nejsou uvedeny), `TimeZone`/`DateFormatter` | žádné | S | nízké; kurz se vyhlašuje po 14:30, cache do dalšího dne | 3 | **ANO** |

Poznámky k duplicitám: Pomodoro už je ve `FocusTimer`, proto není v tabulce samostatně; je možné jen přidat režim "práce/pauza" jako rozšíření.

## 3. Šest funkcí vhodných pro izolovanou implementaci

Splňují: jeden nový soubor služby + jedno view, žádné nové oprávnění, žádná změna cizího kódu kromě registrace.

1. **Systémové statistiky (#1)**: priorita 5, nejlevnější a konkurence ji má (Atoll).
2. **Rychlé poznámky (#2)**: priorita 5, jen soubor v Application Support.
3. **Počasí (#3)**: priorita 4, Open-Meteo bez klíče, město zadané ručně (vyhne se CoreLocation).
4. **Indikátor mikrofonu a kamery (#5)**: priorita 4, unikátní "soukromí" prvek za malé peníze; bez názvu aplikace.
5. **Spouštěč Zkratek (#7)**: priorita 4, využije celý ekosystém Zkratek místo vlastních integrací.
6. **Připomínka pauzy (#9)**: priorita 4, jen čtení doby nečinnosti.

Další dobří kandidáti: **Color picker (#6)**, **časovač po klientech (#8)** a **kurzy ČNB (#20)**, taky izolované. **Globální zkratka (#4)** má nejvyšší hodnotu, ale potřebuje jedno volání do `NotchViewModel`, proto není v šestici.

Doporučené pořadí: #4, #1, #2, #9, #7, #3, potom #11 (lyrics) a #12 (smart shelf) jako větší hodnota, pak #10 (clipboard) až po ověření chování pasteboard alertu na reálném macOS 26.

## 4. Co se nedoporučuje

- **Přehrávání z prohlížečů přes MediaRemote**: od macOS 15.4 nefunguje přímo z aplikace, obchází se přes `/usr/bin/perl` (mediaremote-adapter, sám autor varuje před rozbitím při dalším updatu). Porušuje podmínku neudržovaných/soukromých API.
- **Jas přes `DisplayServices`**: privátní framework.
- **Zrcadlení notifikací z Notification Center**: DB vyžaduje Full Disk Access.
- **Stav Focus režimu**: `INFocusStatusCenter` vyžaduje oprávnění a nepřímé čtení souborů Full Disk Access.
- **Název aplikace u mikrofonu/kamery**: veřejné API neexistuje.
- **WeatherKit**: vyžaduje Apple Developer účet.

## 5. Neověřeno / otevřené body

- Zda macOS 26/27 vynucuje pasteboard alert pro třetí strany (zdroje popisují jen náhled od 15.4).
- Chování `sharingType = .none` se ScreenCaptureKit.
- Podmínky použití Open-Meteo, pokud by se NotchMax šířil komerčně.
- NSColorSampler: dokumentace žádné oprávnění nezmiňuje, nutné potvrdit na reálném stroji.
- Existence a tvar `host_processor_info` v aktuální dokumentaci se nepodařilo načíst (stránka Apple vrátila chybu); API se běžně používá, ale před implementací ověř v Xcode.
- RegisterEventHotKey: stránku v dokumentaci Apple se nepodařilo načíst, deprecaci nelze potvrdit z primárního zdroje.
- Všechny funkce počítají s tím, že kód ve repozitáři zatím nebyl zkompilován (viz SPEC, sekce 6).

## 6. Zdroje

- NotchNook srovnání (MacUpdate, affiliate): https://www.macupdate.com/comparisons/notchnook-vs-alcove-whats-the-best-macbook-notch-app-in-2026
- Notchly guide, aktualizace 04/2026 (autorsky zaujatý): https://notchly.vercel.app/blog/best-macbook-notch-apps
- Alcove (SourceForge): https://sourceforge.net/app/alcove/mac/
- Boring.Notch repo a roadmapa: https://github.com/TheBoredTeam/boring.notch
- Boring.Notch v2.7-rc.2: https://newreleases.io/project/github/TheBoredTeam/boring.notch/release/v2.7-rc.2
- Atoll (Atoll-Labs): https://github.com/Atoll-Labs/Atoll
- NotchDrop (Lakr233): https://github.com/Lakr233/NotchDrop
- NotchDrop recenze (Product Hunt): https://www.producthunt.com/products/notchdrop/reviews
- Droppy (Product Hunt): https://www.producthunt.com/products/droppy-4?launch=droppy-4
- Alternativy k NotchNook (AlternativeTo): https://alternativeto.net/software/notchnook/?p=3
- Lyric Fever: https://github.com/aviwad/LyricFever
- Lyricly: https://feedbagel.com/post/lyricly
- mediaremote-adapter: https://github.com/ungive/mediaremote-adapter
- Pasteboard privacy v macOS 15.4 (Michael Tsai): https://mjtsai.com/blog/2025/05/12/pasteboard-privacy-preview-in-macos-15-4
- Dopady pasteboard ochrany na aplikace: https://engineered.at/articles/making-my-app-worse-because-of-macos-privacy-protections
- Apple, `NSPasteboard.accessBehavior`: https://developer.apple.com/tutorials/data/documentation/appkit/nspasteboard/accessbehavior-86972.md
- Apple, `NSColorSampler`: https://developer.apple.com/documentation/appkit/nscolorsampler
- Apple, `CGEventSource.secondsSinceLastEventType`: https://developer.apple.com/documentation/coregraphics/cgeventsource/secondssincelasteventtype(_:eventtype:)
- Apple, `VNRecognizeTextRequest`: https://developer.apple.com/documentation/vision/vnrecognizetextrequest
- Apple, `kCMIODevicePropertyDeviceIsRunningSomewhere`: https://developer.apple.com/documentation/coremediaio/kcmiodevicepropertydeviceisrunningsomewhere
- Apple, `kAudioDevicePropertyDeviceIsRunningSomewhere`: https://developer.apple.com/documentation/coreaudio/kaudiodevicepropertydeviceisrunningsomewhere
- Apple, `NSWindow.sharingType`: https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.property
- Apple Support, Shortcuts CLI: https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac
- Carbon hotkey bez oprávnění a jeho limity: https://dev.to/quicopy/the-macos-global-shortcut-that-wont-fire-in-zed-when-a-23-year-old-carbon-api-meets-a-self-drawn-24o9
- Open-Meteo podmínky: https://open-meteo.com/en/terms
- Open-Meteo geocoding: https://open-meteo.com/en/docs/geocoding-api
- LRCLIB API: https://lrclib.net/docs.txt
- ČNB denní kurzy: https://www.cnb.cz/cs/financni-trhy/devizovy-trh/kurzy-devizoveho-trhu/kurzy-devizoveho-trhu/denni_kurz.txt
- Jas na Apple Silicon (Hammerspoon issue 2668): https://github.com/Hammerspoon/hammerspoon/issues/2668
