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

    /// Klíčovým oknem se panel stává jen na dobu psaní do textového pole. Klíčové okno totiž
    /// přepíná Liquid Glass do „aktivního“ vzhledu (světlejší, šedé), a ten nechceme.
    private var allowsKey = false
    override var canBecomeKey: Bool { allowsKey }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, !isKeyWindow,
           let hit = contentView?.hitTest(event.locationInWindow), Self.isTextInput(hit) {
            allowsKey = true
            makeKey()
        }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        allowsKey = false
    }

    private static func isTextInput(_ view: NSView) -> Bool {
        var v: NSView? = view
        while let cur = v {
            if cur is NSTextView || cur is NSTextField { return true }
            v = cur.superview
        }
        return false
    }
    override var canBecomeMain: Bool { false }

    /// Systém by jinak okno posunul pod menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
