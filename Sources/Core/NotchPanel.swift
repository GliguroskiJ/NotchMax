import AppKit

/// Průhledné okno bez rámečku nad menu barem, které nekrade focus.
final class NotchPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: NotchLayout.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        acceptsMouseMovedEvents = true
        appearance = NSAppearance(named: .darkAqua)
        // Ve výchozím stavu průhledné okno klikání nepřijímá (klikání do menu baru prochází).
        ignoresMouseEvents = true
    }

    /// Panel bez aktivace aplikace, ale s možností psát do textových polí (poznámky, město).
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Systém by jinak okno posunul pod menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
