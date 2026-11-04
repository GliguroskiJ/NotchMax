import SwiftUI
import AppKit

/// Sekce nastavení „Agenti“ – přehled relací Claude Code a hooky.
struct ClaudeSettingsSection: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var monitor = ClaudeMonitor.shared
    @State private var errorMessage: String?
    @State private var infoMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(header: "Zobrazení") {
                SettingsToggleRow(title: "Záložka Agenti",
                                  subtitle: "Přehled relací Claude Code v rozbaleném notchi.",
                                  isOn: $settings.tabAgents)
                SettingsDivider()
                SettingsToggleRow(title: "Živá aktivita u notche",
                                  subtitle: "Když Claude pracuje nebo čeká na tebe, ukáže se stav vedle notche.",
                                  isOn: $settings.liveClaude)
            }

            SettingsCard(header: "Hooky Claude Code") {
                SettingsRow(title: "Stav",
                            subtitle: monitor.hooksInstalled
                                ? "Nainstalováno – NotchMax ví přesně, kdy Claude pracuje, dokončí tah nebo čeká na povolení."
                                : "Nenainstalováno – stav se odhaduje jen z transkriptů, takže „čeká na tebe“ se nepozná.") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(monitor.hooksInstalled ? Color.green : Color.white.opacity(0.3))
                            .frame(width: 8, height: 8)
                        Text(monitor.hooksInstalled ? "Aktivní" : "Neaktivní")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.75))
                    }
                }
                SettingsDivider()
                SettingsRow(title: monitor.hooksInstalled ? "Odinstalovat hooky" : "Instalovat hooky",
                            subtitle: "Upraví ~/.claude/settings.json (původní obsah zůstane, záloha v settings.json.notchmax-backup). Platí pro nově spuštěné relace.") {
                    HStack(spacing: 8) {
                        if monitor.hooksInstalled {
                            Button("Přeinstalovat") { install() }
                                .controlSize(.regular)
                            Button("Odinstalovat hooky", role: .destructive) { uninstall() }
                                .controlSize(.regular)
                        } else {
                            Button("Instalovat hooky") { install() }
                                .controlSize(.regular)
                        }
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
                             text: "Hooky na události SessionStart, UserPromptSubmit, PreToolUse, Notification, Stop a SessionEnd jen připíšou řádek do ~/Library/Application Support/NotchMax/claude-events.jsonl (pomocí tr, date a printf, které jsou v každém macOS). Nic neblokují, nic nevypisují do konverzace a nikam se neposílají. Odinstalace odstraní jen položky označené „NotchMax“.")
            }

            SettingsCard(header: "Relace") {
                SettingsRow(title: "Nalezené relace",
                            subtitle: "Za posledních 24 hodin: \(monitor.sessions.count) · pracuje \(monitor.workingCount) · čeká \(monitor.waitingCount)") {
                    HStack(spacing: 8) {
                        Button("Obnovit") { monitor.refresh() }
                        Button("Otevřít ~/.claude") { openClaudeFolder() }
                    }
                }
                SettingsDivider()
                SettingsNote(symbol: "eye.slash",
                             text: "Vidět jsou jen relace Claude Code (CLI v terminálu, případně v IDE) na tomto Macu – čtou se z ~/.claude/projects. Konverzace v aplikaci Claude pro desktop ani chaty na claude.ai se lokálně neukládají, takže je NotchMax zobrazit nemůže.")
            }
        }
    }

    private func install() {
        do {
            try monitor.installHooks()
            errorMessage = nil
            infoMessage = "Hooky jsou nainstalované. Projeví se v nově spuštěných relacích Claude Code (běžící relaci restartuj)."
        } catch {
            infoMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func uninstall() {
        do {
            try monitor.uninstallHooks()
            errorMessage = nil
            infoMessage = "Hooky NotchMax byly odebrány, ostatní nastavení zůstalo beze změny."
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
