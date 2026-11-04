import AppKit
import ApplicationServices
import Combine

/// Zachytává systémové „media“ klávesy (hlasitost, jas, podsvícení klávesnice, přehrávání)
/// přes CGEventTap. Pokud je zapnuté `hudReplaceSystem`, změnu provede sám, ukáže HUD v notchi
/// a událost spolkne, takže se nezobrazí systémové OSD. Mediální klávesy se nikdy nespolykají,
/// jen se oznámí `MediaHUDBridge`.
/// Vyžaduje oprávnění Zpřístupnění (Accessibility).
@MainActor
final class MediaKeyInterceptor {
    static let shared = MediaKeyInterceptor()

    // NX_KEYTYPE_* (IOKit/hidsystem/ev_keymap.h)
    private enum Key {
        static let soundUp = 0
        static let soundDown = 1
        static let brightnessUp = 2
        static let brightnessDown = 3
        static let mute = 7
        static let play = 16
        static let next = 17
        static let previous = 18
        static let fast = 19
        static let rewind = 20
        static let illuminationUp = 21
        static let illuminationDown = 22
    }

    private static let normalStep = 1.0 / 16.0
    private static let fineStep = 1.0 / 64.0

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var trustPollTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var started = false
    /// Klávesy, jejichž keyDown jsme spolkli – spolkne se i odpovídající keyUp.
    private var swallowedKeys = Set<Int>()
    /// Převíjecí klávesy (FAST/REWIND), které se právě drží (přišel repeat).
    private var heldSeekKeys = Set<Int>()

    private var replaceSystem = false
    private var mediaHUD = false

    private init() {}

    // MARK: - Oprávnění

    var isTrusted: Bool { AXIsProcessTrusted() }

    /// Zobrazí systémový dialog s žádostí o oprávnění Zpřístupnění.
    func requestAccess() {
        // Hodnota kAXTrustedCheckOptionPrompt; literál obchází rozdíly v importu (Unmanaged vs. CFString) mezi SDK.
        let key = "AXTrustedCheckOptionPrompt"
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        updateState()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Je event tap aktivní?
    var isActive: Bool { tap != nil }

    // MARK: - Životní cyklus

    func start() {
        guard !started else { return }
        started = true
        let settings = AppSettings.shared
        replaceSystem = settings.hudReplaceSystem
        mediaHUD = settings.hudMedia

        // @Published posílá hodnotu ve willSet → pracujeme s předanými hodnotami.
        settings.$hudReplaceSystem
            .combineLatest(settings.$hudMedia)
            .receive(on: RunLoop.main)
            .sink { [weak self] values in
                guard let self else { return }
                self.replaceSystem = values.0
                self.mediaHUD = values.1
                self.updateState()
            }
            .store(in: &cancellables)

        updateState()
    }

    /// Nainstaluje / odinstaluje tap podle nastavení a oprávnění.
    private func updateState() {
        let wanted = replaceSystem || mediaHUD
        guard wanted else {
            stopTrustPolling()
            removeTap()
            return
        }
        if tap != nil { return }
        if isTrusted {
            stopTrustPolling()
            installTap()
            if tap == nil { startTrustPolling() } // např. oprávnění ještě nedorazilo
        } else {
            startTrustPolling()
        }
    }

    private func startTrustPolling() {
        guard trustPollTimer == nil else { return }
        trustPollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
            Task { @MainActor in
                let me = MediaKeyInterceptor.shared
                guard me.tap == nil else { me.stopTrustPolling(); return }
                if me.isTrusted { me.installTap() }
                if me.tap != nil { me.stopTrustPolling() }
            }
        }
    }

    private func stopTrustPolling() {
        trustPollTimer?.invalidate()
        trustPollTimer = nil
    }

    private func installTap() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << 14) // NSEvent.EventType.systemDefined
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: mediaKeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        runLoopSource = source
    }

    private func removeTap() {
        if let port = tap {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        swallowedKeys.removeAll()
        heldSeekKeys.removeAll()
    }

    fileprivate func reenableTap() {
        if let port = tap { CGEvent.tapEnable(tap: port, enable: true) }
    }

    // MARK: - Zpracování kláves

    /// Vrací true, pokud se má událost spolknout.
    fileprivate func handle(keyCode: Int, keyDown: Bool, isRepeat: Bool, fine: Bool) -> Bool {
        switch keyCode {
        case Key.play, Key.next, Key.previous:
            if keyDown && !isRepeat {
                let action: MediaAction
                switch keyCode {
                case Key.next: action = .next
                case Key.previous: action = .previous
                default: action = .play // přepnutí přehrávání; skutečný stav dořeší MediaHUDBridge
                }
                MediaHUDBridge.shared.mediaKeyPressed(action)
            }
            return false

        case Key.fast, Key.rewind:
            // Apple klávesnice (F7/F9): krátký stisk = předchozí/další, podržení = převíjení.
            // Rozhodne se až při puštění – podržení (repeat) HUD nezobrazí.
            if keyDown {
                if isRepeat { heldSeekKeys.insert(keyCode) } else { heldSeekKeys.remove(keyCode) }
            } else if heldSeekKeys.remove(keyCode) == nil {
                MediaHUDBridge.shared.mediaKeyPressed(keyCode == Key.fast ? .next : .previous)
            }
            return false

        case Key.soundUp, Key.soundDown, Key.mute,
             Key.brightnessUp, Key.brightnessDown,
             Key.illuminationUp, Key.illuminationDown:
            guard replaceSystem else {
                swallowedKeys.removeAll()
                return false
            }
            if !keyDown {
                return swallowedKeys.remove(keyCode) != nil
            }
            // Podržení mute neopakujeme.
            if keyCode == Key.mute && isRepeat {
                return swallowedKeys.contains(keyCode)
            }
            let ok = perform(keyCode: keyCode, fine: fine)
            if ok { swallowedKeys.insert(keyCode) } else { swallowedKeys.remove(keyCode) }
            return ok

        default:
            return false
        }
    }

    /// Provede změnu a ukáže HUD. false = nepodařilo se, událost nechat systému.
    private func perform(keyCode: Int, fine: Bool) -> Bool {
        let step = fine ? Self.fineStep : Self.normalStep
        switch keyCode {
        case Key.soundUp, Key.soundDown:
            guard let state = SystemControls.adjustVolume(steps: keyCode == Key.soundUp ? 1 : -1, step: step)
            else { return false }
            HUDCenter.shared.show(.volume(level: state.level, muted: state.muted))
            return true
        case Key.mute:
            guard let state = SystemControls.toggleMute() else { return false }
            HUDCenter.shared.show(.volume(level: state.level, muted: state.muted))
            return true
        case Key.brightnessUp, Key.brightnessDown:
            guard let level = SystemControls.adjustDisplayBrightness(
                steps: keyCode == Key.brightnessUp ? 1 : -1, step: step)
            else { return false }
            HUDCenter.shared.show(.brightness(level: level))
            return true
        case Key.illuminationUp, Key.illuminationDown:
            guard let level = SystemControls.adjustKeyboardBrightness(
                steps: keyCode == Key.illuminationUp ? 1 : -1, step: step)
            else { return false }
            HUDCenter.shared.show(.keyboardBrightness(level: level))
            return true
        default:
            return false
        }
    }
}

// MARK: - C callback (bez zachycených proměnných)

private let mediaKeyTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let interceptor = Unmanaged<MediaKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { interceptor.reenableTap() }
        return Unmanaged.passUnretained(event)
    }

    // NX_SYSDEFINED = 14 (nemá vlastní case v CGEventType).
    guard type.rawValue == 14 else { return Unmanaged.passUnretained(event) }

    // Tap běží na hlavním run loopu → jsme na hlavním vlákně.
    let swallow: Bool = MainActor.assumeIsolated {
        guard let nsEvent = NSEvent(cgEvent: event), nsEvent.subtype.rawValue == 8 else { return false }
        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF0000) >> 16
        let keyFlags = data1 & 0x0000FFFF
        let keyDown = ((keyFlags & 0xFF00) >> 8) == 0xA
        let isRepeat = (keyFlags & 0x1) != 0
        let mods = nsEvent.modifierFlags
        let fine = mods.contains(.option) && mods.contains(.shift)
        return interceptor.handle(keyCode: keyCode, keyDown: keyDown, isRepeat: isRepeat, fine: fine)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
