import SwiftUI

@main
struct NotchMaxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("NotchMax", systemImage: "rectangle.topthird.inset.filled") {
            MenuContent()
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

/// Vlastní okno Nastavení. Scéna `Settings` z panelu bez fokusu spolehlivě neotevřela okno.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView().withServices())
            let w = NSWindow(contentViewController: host)
            w.title = "NotchMax"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.appearance = NSAppearance(named: .darkAqua)
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

@MainActor
func openNotchMaxSettings() {
    SettingsWindowController.shared.show()
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
