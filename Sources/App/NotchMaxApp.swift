import SwiftUI

@main
struct NotchMaxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Aplikace nemá ikonku v menu baru; Nastavení se otevírá ozubeným kolem v panelu notche.
        Settings { EmptyView() }
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
            let size = NSSize(width: 900, height: 620)
            let hosting = NSHostingView(rootView: SettingsView().withServices())
            hosting.sizingOptions = []
            // Zaoblené rohy celého okna zajistí maska na kontejneru (průhledné okno nemá systémové rohy).
            let container = NSView(frame: NSRect(origin: .zero, size: size))
            container.wantsLayer = true
            container.layer?.cornerRadius = 20
            container.layer?.cornerCurve = .continuous
            container.layer?.masksToBounds = true
            hosting.frame = container.bounds
            hosting.autoresizingMask = [.width, .height]
            container.addSubview(hosting)

            let w = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.contentView = container
            w.title = "NotchMax"
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isOpaque = false
            w.backgroundColor = .clear
            w.standardWindowButton(.zoomButton)?.isEnabled = false
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
