import AppKit
import Combine
import IOKit.pwr_mgt

/// Focus časovač + „nenechat Mac usnout“ + volitelné zapnutí macOS Soustředění
/// (přes uživatelovy Apple Zkratky, protože veřejné API pro Focus neexistuje).
@MainActor
final class FocusTimer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var total: TimeInterval = 0
    @Published var keepAwake = false {
        didSet { updateAssertion() }
    }
    /// Chyba při zapínání/vypínání Soustředění (např. chybějící zkratka).
    @Published var focusError: String?
    /// `true`, pokud jsme při startu časovače spustili zkratku pro zapnutí Soustředění.
    @Published private(set) var focusActive = false

    private var endDate: Date?
    private var ticker: Timer?
    private var assertionID: IOPMAssertionID = 0

    /// 0…1, kolik času už uběhlo
    var progress: Double {
        total > 0 ? min(max(1 - remaining / total, 0), 1) : 0
    }

    var display: String {
        let secs = Int(ceil(remaining))
        return String(format: "%02d:%02d", secs / 60, secs % 60)
    }

    /// Čas, kdy časovač skončí (nil, když neběží).
    var endTime: Date? { endDate }

    func start(minutes: Int) {
        total = Double(minutes * 60)
        remaining = total
        endDate = Date().addingTimeInterval(total)
        isRunning = true
        ticker?.invalidate()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t

        if AppSettings.shared.focusWithTimer, !focusActive {
            setFocus(on: true)
        }
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        endDate = nil
        isRunning = false
        remaining = 0
        total = 0

        if focusActive {
            setFocus(on: false)
        }
    }

    private func tick() {
        guard let end = endDate else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        if remaining <= 0 {
            stop()
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
    }

    // MARK: - Soustředění přes Zkratky

    private func setFocus(on: Bool) {
        let settings = AppSettings.shared
        let raw: String = on ? settings.focusOnShortcut : settings.focusOffShortcut
        let name: String = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Při vypínání se stav ruší vždy; při zapínání až po úspěšné kontrole níže.
        if !on { focusActive = false }

        guard !name.isEmpty else {
            focusError = on ? "Není nastavena zkratka pro zapnutí Soustředění" : "Není nastavena zkratka pro vypnutí Soustředění"
            return
        }

        let store = ShortcutsStore.shared
        if store.hasLoaded && !store.contains(name) {
            focusError = "Zkratka „\(name)“ neexistuje"
            return
        }

        focusError = nil
        if on { focusActive = true }
        store.runSilently(name) { [weak self] message in
            guard let self else { return }
            if message.localizedCaseInsensitiveContains("find") || message.localizedCaseInsensitiveContains("not found") {
                self.focusError = "Zkratka „\(name)“ neexistuje"
            } else {
                self.focusError = "Soustředění: \(message)"
            }
        }
    }

    // MARK: - Nenechat usnout

    private func updateAssertion() {
        if keepAwake {
            guard assertionID == 0 else { return }
            IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "NotchMax: nenechat Mac usnout" as CFString,
                &assertionID
            )
        } else if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
    }
}
