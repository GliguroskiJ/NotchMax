import AppKit
import SwiftUI

/// Nastavení „Soustředění s časovačem“: při startu focus časovače NotchMax sám zapne
/// macOS „Nerušit“ (přes Ovládací centrum a oprávnění Zpřístupnění), po skončení ho vypne.
struct FocusSettingsSection: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var focus = FocusController.shared

    @State private var isTesting = false
    @State private var testResult: String?
    @State private var testSucceeded = false

    @State private var isExporting = false
    @State private var diagnosticsPath: String?
    @State private var diagnosticsFailed = false

    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(header: L("Soustředění s časovačem")) {
                SettingsToggleRow(title: L("Zapnout Nerušit s časovačem"),
                                  subtitle: L("Při spuštění focus časovače se zapne Nerušit, po skončení nebo zastavení se zase vypne."),
                                  isOn: $settings.focusWithTimer)
                SettingsDivider()
                SettingsNote(symbol: "moon.fill",
                             text: L("NotchMax přepíná „Nerušit“ automaticky – nic dalšího nastavovat nemusíš. Pokud už bylo Nerušit zapnuté před spuštěním časovače, po skončení ho nechá zapnuté."))
            }

            SettingsCard(header: L("Oprávnění")) {
                PermissionRow(kind: .accessibility, compact: true)
                SettingsDivider()
                SettingsNote(symbol: "info.circle",
                             text: L("NotchMax na okamžik otevře v menu baru Soustředění (nebo Ovládací centrum), přepne „Nerušit“ a menu zase zavře. Bez oprávnění Zpřístupnění to nejde. Po aktualizaci nepodepsaného sestavení může být potřeba NotchMax v seznamu Zpřístupnění odebrat (−) a přidat znovu (+)."))
            }

            SettingsCard(header: L("Vyzkoušet")) {
                SettingsRow(title: L("Vyzkoušet Nerušit"),
                            subtitle: testSubtitle) {
                    HStack(spacing: 8) {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        GlassPill(title: L("Vyzkoušet"), symbol: "moon.fill") {
                            runTest()
                        }
                        .fixedSize()
                        .disabled(isTesting)
                        .opacity(isTesting ? 0.5 : 1)
                    }
                    .fixedSize()
                }
                if let error = focus.lastError, !isTesting, !testSucceeded {
                    SettingsDivider()
                    SettingsNote(symbol: "exclamationmark.triangle", text: error)
                }
            }

            SettingsCard(header: L("Diagnostika")) {
                SettingsActionRow(title: L("Diagnostický záznam"),
                                  subtitle: L("Uloží do souboru stav Soustředění, oprávnění a poslední pokusy o přepnutí Nerušit. Hodí se při hlášení chyby.")) {
                    GlassPill(title: L("Diagnostika"), symbol: "stethoscope") {
                        exportDiagnostics()
                    }
                    .fixedSize()
                    .disabled(isExporting)
                    .opacity(isExporting ? 0.5 : 1)
                    if let path = diagnosticsPath {
                        GlassPill(title: L("Zobrazit ve Finderu"), symbol: "folder") {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                        }
                        .fixedSize()
                    }
                }
                if let path = diagnosticsPath {
                    SettingsDivider()
                    SettingsNote(symbol: "doc.text", text: L("Uloženo: %@", path))
                } else if diagnosticsFailed {
                    SettingsDivider()
                    SettingsNote(symbol: "exclamationmark.triangle",
                                 text: L("Diagnostiku se nepodařilo uložit."))
                }
            }
        }
        .onAppear { refreshPermissions() }
        .onReceive(refreshTimer) { _ in refreshPermissions() }
    }

    // MARK: - Pomocné

    private var testSubtitle: String {
        if let testResult { return testResult }
        if !focus.method.isEmpty { return L("Naposledy fungovalo: %@", L(focus.method)) }
        return L("Zapne Nerušit a po 3 s ho zase vypne.")
    }

    private func refreshPermissions() {
        PermissionCenter.shared.refresh()
        focus.refreshPermission()
    }

    private func exportDiagnostics() {
        guard !isExporting else { return }
        isExporting = true
        Task { @MainActor in
            let path: String? = await FocusController.shared.exportDiagnostics()
            diagnosticsPath = path
            diagnosticsFailed = path == nil
            isExporting = false
        }
    }

    private func runTest() {
        guard !isTesting else { return }
        isTesting = true
        testSucceeded = false
        testResult = L("Zapínám Nerušit…")
        Task { @MainActor in
            let onResult: FocusChangeResult = await FocusController.shared.apply(true)
            guard onResult.ok else {
                testResult = L("Nepodařilo se zapnout: %@", onResult.error ?? L("neznámá chyba"))
                isTesting = false
                return
            }
            if !onResult.changed {
                // Nerušit už bylo zapnuté – nevypínat uživateli jeho vlastní režim.
                testResult = L("Nerušit už bylo zapnuté – funguje (%@).", L(onResult.method))
                testSucceeded = true
                isTesting = false
                return
            }
            testResult = L("Nerušit zapnuto – vypnu za 3 s…")
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            testResult = L("Vypínám Nerušit…")
            let offResult: FocusChangeResult = await FocusController.shared.apply(false)
            if offResult.ok {
                testResult = L("Funguje ✓ (%@)", L(onResult.method))
                testSucceeded = true
            } else {
                testResult = L("Zapnutí fungovalo, vypnutí ne: %@", offResult.error ?? L("neznámá chyba"))
            }
            isTesting = false
        }
    }
}
