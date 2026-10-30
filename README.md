# NotchMax

Aplikace pro macOS, která z notche na MacBooku dělá užitečné místo: přehrávač, kalendář, odkladiště souborů, časovač a živé aktivity. Vzhled je černý (splývá s notchem) s prvky Liquid Glass.

## Instalace (uživatel)

1. Stáhni `NotchMax-x.y.z.dmg` z [Releases](../../releases).
2. Přetáhni `NotchMax.app` do složky **Aplikace**. Z DMG ani ze Stažených ji nespouštěj, update by pak nefungoval.
3. První spuštění: aplikace není notarizovaná, takže macOS ukáže varování. Otevři **Nastavení systému → Soukromí a zabezpečení → Přesto otevřít**, nebo v Terminálu:
   ```
   xattr -dr com.apple.quarantine /Applications/NotchMax.app
   ```
4. Při prvním použití macOS požádá o přístup ke Kalendáři a k ovládání Hudby/Spotify (Automatizace). Obojí je potřeba jen pro příslušnou funkci.

Aktualizace: aplikace sama kontroluje nové verze (při startu, po probuzení Macu, jednou denně a v Nastavení → Aktualizace). Nainstaluje je až po tvém potvrzení.

## Vývoj

Vyžaduje Mac s Xcode 26 (kvůli nativnímu Liquid Glass; s Xcode 15/16 se zkompiluje fallback sklo).

```
brew install xcodegen
xcodegen generate
open NotchMax.xcodeproj
```

Struktura:

- `Sources/Core`: okno nad menu barem, tvar notche, hover a tažení souborů
- `Sources/Services`: baterie, média, kalendář, odkladiště, časovač, aktualizace, nastavení
- `Sources/Design`: Liquid Glass s fallbackem, glow a animace
- `Sources/Views`: rozbalený panel, záložky, nastavení

## Vydání nové verze (git push → update)

Jednorázové nastavení:

1. `SUFeedURL` v `project.yml` už míří na `github.com/GliguroskiJ/NotchMax` (repozitář musí být veřejný, jinak se update nestáhne).
2. Stáhni [Sparkle](https://github.com/sparkle-project/Sparkle/releases) a spusť `bin/generate_keys`. Vypíše **veřejný klíč**, ten vlož do `SUPublicEDKey` v `project.yml`.
3. Privátní klíč exportuj `bin/generate_keys -x sparkle_private.key`, jeho obsah ulož do GitHub Secret **`SPARKLE_ED_PRIVATE_KEY`**, soubor smaž a zálohuj do správce hesel. Bez něj už nelze vydat update.
4. Volitelné, ale doporučené: vytvoř v Přístupu k klíčence self-signed certifikát typu Code Signing (platnost 10+ let), exportuj `.p12` a ulož base64 do secretů `MACOS_CERT_P12` a `MACOS_CERT_PASSWORD`. Díky stabilnímu podpisu se po updatu neresetují oprávnění (Kalendář, Automatizace).

Každé další vydání:

```
git tag v0.1.1
git push origin v0.1.1
```

GitHub Actions appku sestaví, podepíše, vytvoří `.zip` a `.dmg`, vygeneruje `appcast.xml` a vydá je jako GitHub Release. Nainstalované aplikace si novou verzi načtou samy.

## Bezpečnost

- V repozitáři nejsou žádná tajemství. Podpisový klíč a certifikát jsou jen v GitHub Secrets.
- `.gitignore` blokuje `*.key`, `*.p12`, `*.pem` a `Config/Secrets.xcconfig`.
- Zapni si na GitHubu Secret scanning a Push protection a 2FA na účtu: kdo ovládne secrets, může podepsat škodlivý update.

## Co je hotové a co ne

Viz [docs/SPEC.md](docs/SPEC.md).
