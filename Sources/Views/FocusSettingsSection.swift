import AppKit
import SwiftUI

/// Nastavení „Soustředění s časovačem“: při startu focus časovače se spustí zkratka
/// pro zapnutí macOS Soustředění, po skončení / zastavení zkratka pro vypnutí.
struct FocusSettingsSection: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var store = ShortcutsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(header: "Soustředění s časovačem") {
                SettingsRow(title: "Zapnout Soustředění s časovačem",
                            subtitle: "Při spuštění časovače zapne Soustředění, po skončení ho vypne.") {
                    Toggle("", isOn: $settings.focusWithTimer)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(settings.accent.color)
                }
                SettingsDivider()
                SettingsRow(title: "Zkratka pro zapnutí", subtitle: status(for: settings.focusOnShortcut)) {
                    shortcutPicker(selection: $settings.focusOnShortcut)
                }
                SettingsDivider()
                SettingsRow(title: "Zkratka pro vypnutí", subtitle: status(for: settings.focusOffShortcut)) {
                    shortcutPicker(selection: $settings.focusOffShortcut)
                }
                SettingsDivider()
                SettingsRow(title: "Seznam zkratek",
                            subtitle: store.hasLoaded ? "Načteno zkratek: \(store.shortcuts.count)" : "Zatím nenačteno") {
                    HStack(spacing: 8) {
                        if store.isReloading {
                            ProgressView()
                                .controlSize(.small)
                        }
                        GlassPill(title: "Načíst zkratky", symbol: "arrow.clockwise") {
                            store.reload()
                        }
                    }
                }
            }

            SettingsCard(header: "Jak to nastavit") {
                SettingsNote(symbol: "1.circle",
                             text: "Otevři aplikaci Zkratky a vytvoř zkratku „NotchMax Focus On“.")
                SettingsDivider()
                SettingsNote(symbol: "2.circle",
                             text: "Přidej akci „Nastavit soustředění“ → Zapnout „Nerušit“ (nebo vlastní režim soustředění).")
                SettingsDivider()
                SettingsNote(symbol: "3.circle",
                             text: "Vytvoř druhou zkratku „NotchMax Focus Off“ se stejnou akcí nastavenou na Vypnout.")
                SettingsDivider()
                SettingsNote(symbol: "4.circle",
                             text: "Vrať se sem, klikni na „Načíst zkratky“ a vyber je výše. Pak zapni přepínač.")
                SettingsDivider()
                SettingsRow(title: "Aplikace Zkratky") {
                    GlassPill(title: "Otevřít Zkratky", symbol: "arrow.up.forward") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
                    }
                }
            }
        }
        .onAppear {
            if !store.hasLoaded { store.reload() }
        }
    }

    // MARK: - Pomocné

    private func shortcutPicker(selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            ForEach(options(including: selection.wrappedValue), id: \.self) { name in
                Text(name).tag(name)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: 220)
    }

    /// Načtené zkratky + aktuální hodnota, pokud mezi nimi chybí.
    private func options(including current: String) -> [String] {
        var list: [String] = store.shortcuts
        if !current.isEmpty && !list.contains(current) {
            list.insert(current, at: 0)
        }
        return list
    }

    private func status(for name: String) -> String? {
        guard store.hasLoaded else { return nil }
        if name.isEmpty { return "Není vybrána žádná zkratka." }
        return store.contains(name) ? nil : "Zkratka „\(name)“ zatím neexistuje."
    }
}
