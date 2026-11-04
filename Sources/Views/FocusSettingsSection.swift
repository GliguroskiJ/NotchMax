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

    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(header: "Soustředění s časovačem") {
                SettingsToggleRow(title: "Zapnout Nerušit s časovačem",
                                  subtitle: "Při spuštění focus časovače se zapne Nerušit, po skončení nebo zastavení se zase vypne.",
                                  isOn: $settings.focusWithTimer)
                SettingsDivider()
                SettingsNote(symbol: "moon.fill",
                             text: "NotchMax přepíná „Nerušit“ automaticky – nic dalšího nastavovat nemusíš. Pokud už bylo Nerušit zapnuté před spuštěním časovače, po skončení ho nechá zapnuté.")
            }

            SettingsCard(header: "Oprávnění") {
                PermissionRow(kind: .accessibility, compact: true)
                SettingsDivider()
                SettingsNote(symbol: "info.circle",
                             text: "NotchMax na okamžik otevře v menu baru Soustředění (nebo Ovládací centrum), přepne „Nerušit“ a menu zase zavře. Bez oprávnění Zpřístupnění to nejde. Po aktualizaci nepodepsaného sestavení může být potřeba NotchMax v seznamu Zpřístupnění odebrat (−) a přidat znovu (+).")
            }

            SettingsCard(header: "Vyzkoušet") {
                SettingsRow(title: "Vyzkoušet Nerušit",
                            subtitle: testSubtitle) {
                    HStack(spacing: 8) {
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                        GlassPill(title: "Vyzkoušet", symbol: "moon.fill") {
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
        }
        .onAppear { refreshPermissions() }
        .onReceive(refreshTimer) { _ in refreshPermissions() }
    }

    // MARK: - Pomocné

    private var testSubtitle: String {
        if let testResult { return testResult }
        if !focus.method.isEmpty { return "Naposledy fungovalo: \(focus.method)" }
        return "Zapne Nerušit a po 3 s ho zase vypne."
    }

    private func refreshPermissions() {
        PermissionCenter.shared.refresh()
        focus.refreshPermission()
    }

    private func runTest() {
        guard !isTesting else { return }
        isTesting = true
        testSucceeded = false
        testResult = "Zapínám Nerušit…"
        Task { @MainActor in
            let onResult: FocusChangeResult = await FocusController.shared.apply(true)
            guard onResult.ok else {
                testResult = "Nepodařilo se zapnout: \(onResult.error ?? "neznámá chyba")"
                isTesting = false
                return
            }
            if !onResult.changed {
                // Nerušit už bylo zapnuté – nevypínat uživateli jeho vlastní režim.
                testResult = "Nerušit už bylo zapnuté – funguje (\(onResult.method))."
                testSucceeded = true
                isTesting = false
                return
            }
            testResult = "Nerušit zapnuto – vypnu za 3 s…"
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            testResult = "Vypínám Nerušit…"
            let offResult: FocusChangeResult = await FocusController.shared.apply(false)
            if offResult.ok {
                testResult = "Funguje ✓ (\(onResult.method))"
                testSucceeded = true
            } else {
                testResult = "Zapnutí fungovalo, vypnutí ne: \(offResult.error ?? "neznámá chyba")"
            }
            isTesting = false
        }
    }
}
