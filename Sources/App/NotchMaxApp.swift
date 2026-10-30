import SwiftUI

@main
struct NotchMaxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("NotchMax", systemImage: "rectangle.topthird.inset.filled") {
            MenuContent()
        }

        Settings {
            SettingsView()
                .withServices()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchWindowController?
    private var screenObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Aplikace je jen v tmavé variantě (notch je černý).
        NSApp.appearance = NSAppearance(named: .darkAqua)
        createController()
        if controller == nil {
            // Žádný displej (např. po probuzení): zkusit znovu při změně displejů.
            screenObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.createController() }
            }
        }
    }

    private func createController() {
        guard controller == nil else { return }
        controller = NotchWindowController()
        if controller != nil, let obs = screenObserver {
            NotificationCenter.default.removeObserver(obs)
            screenObserver = nil
        }
    }
}

/// Otevře okno Nastavení. Nezávisí na SwiftUI scéně, takže funguje i z panelu notche.
@MainActor
func openNotchMaxSettings() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
}

private struct MenuContent: View {
    var body: some View {
        Button("Nastavení…") { openNotchMaxSettings() }
            .keyboardShortcut(",")

        Button("Vyzkoušet animaci nabíjení") {
            AppServices.shared.viewModel?.runChargeAnimation()
        }

        Button("Zkontrolovat aktualizace…") {
            AppServices.shared.updates.checkNow()
        }

        Divider()

        Button("Ukončit NotchMax") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
