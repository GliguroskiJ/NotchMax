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
        // Služby, které posílají HUD události do notche (každá sama respektuje své nastavení).
        MediaKeyInterceptor.shared.start()
        HeadphonesMonitor.shared.start()
        FocusModeMonitor.shared.start()
        ClaudeHUDBridge.shared.start()
        MediaHUDBridge.shared.start()
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
    private var windowObservers: [NSObjectProtocol] = []

    /// Poloměr rohů okna (maska kontejneru).
    static let cornerRadius: CGFloat = 20
    /// Vzdálenost středu tlačítek semaforu od levého a horního okraje – střed leží na středu
    /// zaoblení rohu, takže kroužky jsou s rohem soustředné (jako u oken v macOS 26).
    private static let trafficLightCenterInset: CGFloat = 20

    /// Je okno nastavení právě zobrazené?
    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        if window == nil {
            let size = NSSize(width: 900, height: 620)
            let hosting = NSHostingView(rootView: SettingsView().withServices())
            hosting.sizingOptions = []
            // Zaoblené rohy celého okna zajistí maska na kontejneru (průhledné okno nemá systémové rohy).
            let container = NSView(frame: NSRect(origin: .zero, size: size))
            container.wantsLayer = true
            container.layer?.cornerRadius = SettingsWindowController.cornerRadius
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
            observeLayoutChanges(of: w)
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        repositionTrafficLights()
        // AppKit po zobrazení okna může tlačítka ještě jednou rozmístit – zopakovat v dalším cyklu.
        DispatchQueue.main.async { [weak self] in
            self?.repositionTrafficLights()
        }
    }

    // MARK: Semafor (zavřít / minimalizovat / zoom)

    private func observeLayoutChanges(of window: NSWindow) {
        let names: [Notification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didEndLiveResizeNotification,
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didChangeScreenNotification,
            NSWindow.didChangeBackingPropertiesNotification
        ]
        for name in names {
            let token = NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { _ in
                Task { @MainActor in
                    SettingsWindowController.shared.repositionTrafficLights()
                }
            }
            windowObservers.append(token)
        }
    }

    /// Posune tlačítka semaforu tak, aby byla soustředná s 20bodovým rohem okna.
    /// Zůstávají vlevo, v pořadí zavřít – minimalizovat – zoom, s původní mezerou.
    func repositionTrafficLights() {
        guard let window else { return }
        let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        let buttons: [NSButton] = kinds.compactMap { window.standardWindowButton($0) }
        guard buttons.count == kinds.count,
              let superview = buttons[0].superview else { return }

        // Původní mezera mezi tlačítky (typicky 6 bodů), omezená na 6–8 bodů.
        let gap: CGFloat
        let firstFrame = buttons[0].frame
        let secondFrame = buttons[1].frame
        let measured = secondFrame.minX - firstFrame.maxX
        if measured.isFinite && measured > 0 {
            gap = min(max(measured, 6), 8)
        } else {
            gap = 6
        }

        let inset = SettingsWindowController.trafficLightCenterInset
        let windowHeight = window.frame.height
        var centerX = inset
        for button in buttons {
            let size = button.frame.size
            // Souřadnice okna: počátek vlevo dole.
            let rectInWindow = NSRect(x: (centerX - size.width / 2).rounded(),
                                      y: (windowHeight - inset - size.height / 2).rounded(),
                                      width: size.width,
                                      height: size.height)
            let target = superview.convert(rectInWindow, from: nil)
            if button.frame.origin != target.origin {
                button.setFrameOrigin(target.origin)
            }
            centerX += size.width + gap
        }
    }
}

/// Požadovaná sekce nastavení (např. „calendar“), kterou okno nastavení přepne při otevření.
@MainActor
final class SettingsNavigator: ObservableObject {
    static let shared = SettingsNavigator()
    @Published var requestedSection: String?
}

@MainActor
func openNotchMaxSettings(section: String? = nil) {
    if let section { SettingsNavigator.shared.requestedSection = section }
    SettingsWindowController.shared.show()
}
