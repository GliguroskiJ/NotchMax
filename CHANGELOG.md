# Změny v NotchMax

Poslední sekce se zobrazí v okně aktualizace. Při vydání nové verze přidej nahoru sekci `## x.y.z` (stejné číslo jako tag bez `v`) a pod ni řádky začínající `- `.

## 0.1.11
Úpravy
- Zavřený notch je čistě černý; po rozbalení svítí podle obalu alba nebo zvolené barvy
- Dvě aktivity: hudba jen obal alba, časovač a schůzka jen číslo, obě strany stejně široké
- Odpočet ukazuje stejné minuty jako časovač, poslední minutu vteřiny
- Hlasitost a jas: jednoduchý pruh pod notchem
- Změna skladby: jen animace přepnutí obalu alba, bez textu
- Domovská stránka: menší přehrávač se třemi skleněnými tlačítky, širší kalendář a baterie
- Časovač: 5, 15, 30, 45, 60, 90, 120 a 180 minut ve větší mřížce
- Barva zvýraznění na posuvníku přes celé spektrum
- Přeorganizované nastavení včetně nové stránky Oprávnění a testovacího oznámení
- Opravená tlačítka pro otevření Nastavení systému a detekce plného přístupu k disku
- Tlačítka okna nastavení jsou zarovnaná s rohem jako v aplikacích Applu
- Odebráno přímé přihlášení Google účtu (kalendáře z macOS zůstávají)
- Výchozí poloha notche: posun 0, přesah 1 px

## 0.1.10
Úpravy
- Dvě aktivity vedle notche se vybírají automaticky: ukážou se ty dvě poslední, obě strany jsou stejně široké
- Při dvou aktivitách je hudba jen obal alba; po pozastavení se notch vrátí do souměrného zobrazení
- Časovač a schůzky ukazují odpočet v minutách, poslední minutu ve vteřinách
- Focus časovač zapíná a vypíná Nerušit sám, bez aplikace Zkratky (potřebuje Zpřístupnění)
- V panelu je nejvýš 5 záložek, aby se žádná neschovala za notch
- Tlačítka pro připojení kalendáře jsou zelená
- Agenti (záložka, aktivita i HUD) jsou ve výchozím stavu vypnutí

## 0.1.9
Novinky
- Hlasitost, jas displeje a podsvícení klávesnice se ukazují v notchi místo systémového HUD (potřebuje oprávnění Zpřístupnění)
- Animace při přehrávání: play, pauza, další a předchozí skladba
- Připojení AirPods a sluchátek: točící se animace podle modelu, název a baterie sluchátek i pouzdra
- Animace při přepnutí Soustředění
- Notch blikne, když Claude agent dokončí práci nebo čeká na tebe
- Zrcátko kamery: nové tlačítko vpravo vedle baterie a nastavení
- Oznámení v notchi (experimentální, vyžaduje plný přístup k disku)
- Nová sekce nastavení „HUD a oznámení“

## 0.1.8
Novinky
- Dvě aktivity naráz: vlevo a vpravo od notche si vybereš, co se zobrazí (hudba, časovač, schůzka, baterie, Claude)
- Nová animace nabíjení: pulzy běží po obrysu notche zleva doprava až k bodu podle procent baterie
- Nastavení zúžení levé a pravé strany obrysu nabíjení (Vzhled → Animace nabíjení)
- Statistiky mají 8 ukazatelů: teplota CPU, ventilátory, GPU a energie / zdraví baterie
- Focus časovač umí zapnout a po skončení vypnout Soustředění na Macu (přes Zkratky)
- Nová záložka Agenti s přehledem relací Claude Code
- Google kalendář: výběr kalendářů a přímé přihlášení přes Google
- Nová ikona aplikace
Úpravy
- Skleněný vzhled je stejný, ať do panelu klikneš, nebo ne
- Svítící obrys kolem notche je pryč
- Lepší okraje u živých aktivit vedle notche
- Odebrány Zkratky, Počasí a Poznámky

## 0.1.7
Opravy
- Okno Nastavení se už samo neotevírá po spuštění ani po aktualizaci
- Okno Nastavení má zaoblené všechny rohy
- Notch zůstává Liquid Glass i po kliknutí (panel už nepřepíná sklo do světlého „aktivního“ vzhledu)
- Záložky Systém a Nástroje už neposouvají horní lištu nahoru nebo dolů

## 0.1.6
Opravy
- Okno Nastavení se už samo neotevírá po spuštění ani po aktualizaci
- Okno Nastavení má zaoblené všechny rohy

## 0.1.5
Novinky
- Klik na událost v kalendáři s odkazem na schůzku (Google Meet, Zoom, Teams) ji rovnou otevře; stejně funguje karta další schůzky na Přehledu
- Blížící se schůzka: odpočet v minutách po straně notche posledních 5 minut a má přednost před hudbou i časovačem
- Větší okno Nastavení se zaoblenými rohy
- Aplikace už nemá ikonku v menu baru; Nastavení otevřeš ozubeným kolem v panelu nebo opětovným spuštěním aplikace
- Stabilní podpis aplikace (návod v README), aby si macOS pamatoval oprávnění i po aktualizaci

## 0.1.4
Novinky
- Nastavení → Vzhled: posun notche nahoru nebo dolů o libovolný počet bodů a nastavení přesahu pod fyzický notch
- Výchozí poloha notche je posunutá o 2 px nahoru a přesah pod notch je 2 px, takže tvar sedí v rovině s fyzickým notchem
- Záložky v hlavičce jsou jen ikonky, název už se nezobrazuje a nezasahuje pod notch

## 0.1.3
Novinky
- Záložka Systém: statistiky CPU, paměti, sítě a disku a počasí (Open-Meteo)
- Záložka Nástroje: časovač, spouštěč Zkratek a rychlé poznámky
- Indikátor mikrofonu (oranžová tečka) a kamery (zelená tečka) po straně notche
- Globální zkratka ⌥⌘N pro otevření a zavření notche (jde vypnout v Nastavení)
- Okno aktualizace ukazuje seznam změn přímo jako text
- Živé aktivity po stranách notche jsou užší a nezakrývají menu aplikací
- Víc místa nad ikonami v hlavičce panelu a plynulejší rozbalení

Opravy
- Rámeček pod notchem při změně skladby

## 0.1.2
- Víc místa nad ikonami v hlavičce panelu, plynulejší rozbalení a užší živé aktivity po stranách

## 0.1.1
Novinky
- Nová ikona aplikace
- Přepracovaný vzhled panelu notche: jednotné okraje, soustředné zaoblení, plynulejší animace
- Nastavení ve stylu Apple Music s průsvitným bočním panelem
- Animace nabíjení kolem obrysu notche, nic po stranách
- Okno Nastavení se otevírá spolehlivě z panelu i z menu
- Okno aktualizace ukazuje seznam změn přímo v textu

Opravy
- Kalendář: události „Out of office“ s časem 0:00 už se nezobrazují jako schůzka
- Živé aktivity po stranách notche jsou užší a nezakrývají menu aplikací

## 0.1.0
- První verze: přehrávač, kalendář, odkladiště souborů, časovač, baterie a automatické aktualizace
