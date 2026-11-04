import SwiftUI
import AppKit

/// Sekce nastavení „Agenti“ – přehled relací Claude Code a hooky.
struct ClaudeSettingsSection: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var monitor = ClaudeMonitor.shared
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(header: L("Zobrazení")) {
                TabToggleRow(title: L("Záložka Agenti"),
                             subtitle: L("Přehled relací Claude Code v rozbaleném notchi."),
                             isOn: $settings.tabAgents)
                SettingsDivider()
                SettingsToggleRow(title: L("Živá aktivita u notche"),
                                  subtitle: L("Když Claude pracuje nebo čeká na tebe, ukáže se stav vedle notche."),
                                  isOn: $settings.liveClaude)
            }

            SettingsCard(header: L("Hooky Claude Code")) {
                SettingsRow(title: L("Stav"),
                            subtitle: monitor.hooksInstalled
                                ? L("Nainstalováno – NotchMax ví přesně, kdy Claude pracuje, dokončí tah nebo čeká na povolení.")
                                : L("Nenainstalováno – stav se odhaduje jen z transkriptů, takže „čeká na tebe“ se nepozná.")) {
                    PermissionStatusBadge(text: monitor.hooksInstalled ? L("Aktivní") : L("Neaktivní"),
                                          color: monitor.hooksInstalled ? Color.green : Color.white.opacity(0.3))
                }
                SettingsDivider()
                SettingsActionRow(title: monitor.hooksInstalled ? L("Spravovat hooky") : L("Instalovat hooky"),
                                  subtitle: L("Upraví ~/.claude/settings.json (původní obsah zůstane, záloha v settings.json.notchmax-backup). Platí pro nově spuštěné relace.")) {
                    if monitor.hooksInstalled {
                        GlassPill(title: L("Přeinstalovat"), symbol: "arrow.clockwise") { install() }
                            .fixedSize()
                        GlassPill(title: L("Odinstalovat"), symbol: "trash", tint: Color.red.opacity(0.3)) { uninstall() }
                            .fixedSize()
                    } else {
                        GlassPill(title: L("Instalovat hooky"), symbol: "square.and.arrow.down",
                                  tint: settings.accent.color.opacity(0.35)) { install() }
                            .fixedSize()
                    }
                }
                if let errorMessage {
                    SettingsDivider()
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(Color.orange)
                            .frame(width: 16)
                        Text(errorMessage)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Color.orange.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 12)
                } else if let infoMessage {
                    SettingsDivider()
                    SettingsNote(symbol: "checkmark.circle", text: infoMessage)
                }
                SettingsDivider()
                SettingsNote(symbol: "info.circle",
                             text: L("Hooky na události SessionStart, UserPromptSubmit, PreToolUse, Notification, Stop a SessionEnd jen připíšou řádek do ~/Library/Application Support/NotchMax/claude-events.jsonl (pomocí tr, date a printf, které jsou v každém macOS). Nic neblokují, nic nevypisují do konverzace a nikam se neposílají. Odinstalace odstraní jen položky označené „NotchMax“."))
            }

            SettingsCard(header: L("Relace")) {
                SettingsActionRow(title: L("Nalezené relace"),
                                  subtitle: L("Za posledních 24 hodin: %ld · pracuje %ld · čeká %ld",
                                              monitor.sessions.count, monitor.workingCount, monitor.waitingCount)) {
                    GlassPill(title: L("Obnovit"), symbol: "arrow.clockwise") { monitor.refresh() }
                        .fixedSize()
                    GlassPill(title: L("Otevřít ~/.claude"), symbol: "folder") { openClaudeFolder() }
                        .fixedSize()
                }
                SettingsDivider()
                SettingsNote(symbol: "eye.slash",
                             text: L("Vidět jsou jen relace Claude Code (CLI v terminálu, případně v IDE) na tomto Macu – čtou se z ~/.claude/projects. Konverzace v aplikaci Claude pro desktop ani chaty na claude.ai se lokálně neukládají, takže je NotchMax zobrazit nemůže."))
            }
        }
    }

    private func install() {
        do {
            try monitor.installHooks()
            errorMessage = nil
            infoMessage = L("Hooky jsou nainstalované. Projeví se v nově spuštěných relacích Claude Code (běžící relaci restartuj).")
        } catch {
            infoMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func uninstall() {
        do {
            try monitor.uninstallHooks()
            errorMessage = nil
            infoMessage = L("Hooky NotchMax byly odebrány, ostatní nastavení zůstalo beze změny.")
        } catch {
            infoMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func openClaudeFolder() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        }
    }
}
