# NotchMax: specifikace

Stav k 30. 10. 2026. Aplikace pro macOS 14+, vlastní alternativa k placeným notch aplikacím (NotchNook, Alcove, DynamicLake…). Jen tmavá varianta, černý základ s prvky Liquid Glass.

## 1. Konkurence (shrnutí researche)

Zdroje jsou převážně srovnávací blogy, často psané autory konkurenčních aplikací nebo s affiliate odkazy. Ceny se mezi zdroji rozcházejí, ber je orientačně.

| Aplikace | Cena (orientačně) | Silné stránky | Slabiny |
|---|---|---|---|
| NotchNook | $15–25 jednorázově nebo $2–3/měs. | widgety, tray s AirDropem, gesta, témata | zátěž systému, zahlcenost, bez focus timeru a live activities |
| Alcove | ~$15 | nejlepší animace, více live activities, náhrada HUD | chybí shelf, kalendář, clipboard; macOS 15+, soukromé API |
| DynamicLake | ~$14–17 | hodně funkcí, hovory, notifikace, pluginy | oprávnění (Accessibility), glitche po updatech macOS |
| Boring Notch | zdarma, GPL-3.0 | přehrávač, kalendář, shelf, kamera | nepodepsaný, méně vyladěný, roadmapa bez baterie a notifikací |
| Droppy | ~€9 | shelf s konverzemi, clipboard, kalendář, lyrics | nejsilnější komerční konkurent |
| Notchmeister | zdarma | efekty kolem notche | bez užitku, jen ukázka |

Opakované stížnosti trhu: zahlcenost, zátěž CPU a baterie, požadovaná oprávnění, kolize s fullscreen aplikacemi, rozbití po updatu macOS (soukromá API).

Poznámka: jeden zdroj tvrdí, že NotchNook byl v září 2026 offline kvůli sporu o vlastnictví. Nepotvrzeno, ověř před jakýmkoli závěrem.

## 2. Funkce

### v0.1 (v tomto repozitáři)

- Notch panel nad menu barem, hover pro rozbalení (zpoždění nastavitelné), podpora Maců bez notche (virtuální notch)
- Live aktivity vedle notche: hudba (obal + ekvalizér), focus časovač, blížící se schůzka, nabíjení
- **Nabíjecí animace**: po zapojení nabíječky se notch rozšíří, kolem něj proběhne zelený sweep a naplní se pruh baterie (Liquid Glass kapsle)
- **Svítící obrys kolem notche**: pulzující, rotující (aurora) nebo jemná linka; barva podle aktivity (hudba = akcent, schůzka = oranžová, nabíjení = zelená), u časovače funguje jako ukazatel průběhu
- Přehrávač Apple Music a Spotify (obal, název, ovládání), bez soukromého MediaRemote API
- Kalendář přes EventKit (Google účet přidaný v macOS se objeví sám), tlačítko Připojit pro Zoom / Meet / Teams / Webex
- Odkladiště souborů: tažení souboru na notch otevře odkladiště, soubory se kopírují (přežijí smazání originálu), tažení ven, AirDrop, automatické mazání po zvolené době
- Nástroje: focus časovač, nenechat Mac usnout
- Nastavení: spuštění při přihlášení, displej, akcentní barva, styl glow, přepínání modulů, kalendář, aktualizace
- Aktualizace přes Sparkle 2 z GitHub Releases: kontrola při startu, po probuzení, denně a na tlačítko, vždy s potvrzením uživatele

### Další kroky (v0.2+)

1. Přímé Google OAuth (PKCE, loopback redirect, refresh token v Keychain) pro uživatele bez účtu v macOS
2. Náhrada HUD pro hlasitost a jas
3. Clipboard historie
4. Synchronizované lyrics
5. Globální zkratka pro rozbalení
6. Notifikace s odpovědí
7. Lokalizace (zatím jen čeština)

### Nápady, které konkurence podle researche nemá (neověřeno)

1. **Kontextové režimy**: layout notche se přepíná podle Focus, aplikace v popředí nebo připojeného monitoru (schůzka = jen Připojit a mute)
2. **Strážce mikrofonu a kamery**: v notchi vidíš, která aplikace je právě používá, jedním klikem zakážeš
3. **Chytré cíle při tažení souboru**: zmenšit obrázek, smazat EXIF, OCR, odeslat do složky klienta
4. **Časovač času po klientech** s exportem do CSV
5. **Ochrana při sdílení obrazovky**: notch skryje citlivé notifikace a ukáže indikátor
6. **Náhled posledního screenshotu** s rychlými akcemi (anotace, kopírovat, sdílet)
7. **Připomínka pauzy podle skutečné aktivity** (klávesnice a myš), ne podle pevného časovače
8. **Hledání v clipboardu, souborech a Shortcuts** jednou zkratkou přímo v notchi

## 3. Design

- Celý tvar notche je čistě černý, bez skla a bez horního obrysu, aby splynul s hardwarovým výřezem
- Liquid Glass jen na malých ovládacích prvcích (tlačítka přehrávače, aktivní záložka, pilulky, kapsle baterie), velké plochy jsou matné
- macOS 26+: nativní `glassEffect` a `GlassEffectContainer`; macOS 14/15: fallback z materiálu s odleskem a obrysem; při zapnutém „Omezit průhlednost“ je sklo matnější
- Nativní větev se kompiluje jen s Xcode 26 (`#if compiler(>=6.2)`), jinak se použije fallback i na novém systému
- Animace jsou lehké (24 fps timeline jen když je glow aktivní)

## 4. Architektura

- Jedna aplikace, `LSUIElement`, bez sandboxu (globální monitor myši, Apple Events)
- Projekt generuje XcodeGen z `project.yml`, `.xcodeproj` se necommituje
- `NotchPanel` (NSPanel, průhledný, nad menu barem) + `NotchWindowController` (hover, tažení souborů) + SwiftUI `NotchRootView`
- Služby jako `ObservableObject` v `AppServices`, vložené do prostředí přes `withServices()`

## 5. Distribuce a aktualizace

- Sestavení na GitHub Actions (macOS runner), tag `v*` spustí release: build (universal), podpis, ZIP + DMG, EdDSA podpis, `appcast.xml`, GitHub Release
- Bez placeného Apple Developer účtu: první spuštění vyžaduje „Přesto otevřít“ (návod v README). Self-signed certifikát v secretech udrží stabilní podpis, takže se po updatu neresetují oprávnění
- S Developer ID (99 USD/rok) a notarizací by varování zmizelo; workflow by se rozšířilo o `notarytool` a `stapler`

## 6. Rizika a otevřené body

- **Kód není zkompilovaný**: vznikl bez Xcode, první build proběhne až na macOS runneru; očekávej drobné opravy
- Obal alba z Apple Music (`raw data of artwork`) je potřeba ověřit na reálném stroji
- MediaRemote se nepoužívá, takže přehrávače mimo Music a Spotify (prohlížeče, YouTube) zatím nejsou podporované
- Verze Sparkle a syntaxe `sign_update` v CI se mají ověřit proti aktuální dokumentaci
- Dostupnost Xcode 26 na runneru `macos-15` je potřeba ověřit
- Boring Notch je GPL-3.0, kód se nekopíruje
