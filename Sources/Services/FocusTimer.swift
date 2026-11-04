import AppKit
import Combine
import IOKit.pwr_mgt

/// Focus časovač + „nenechat Mac usnout“ + volitelné zapnutí macOS „Nerušit“
/// (automaticky přes `FocusController`, bez Apple Zkratek).
@MainActor
final class FocusTimer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var total: TimeInterval = 0
    @Published var keepAwake = false {
        didSet { updateAssertion() }
    }
    /// Chyba při zapínání/vypínání Soustředění (např. chybějící oprávnění Zpřístupnění).
    @Published var focusError: String?
    /// `true`, pokud „Nerušit“ zapnul časovač (a po skončení ho tedy zase vypne).
    @Published private(set) var focusActive = false

    private var endDate: Date?
    private var ticker: Timer?
    private var assertionID: IOPMAssertionID = 0
    /// Požadavek na zapnutí „Nerušit“ v řetězu `FocusController` (kvůli správnému vypnutí).
    private var enableRequest: Task<FocusChangeResult, Never>?
    /// Zvyšuje se při každém zapnutí/vypnutí – zastaralé výsledky se ignorují.
    private var focusSession: Int = 0

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
            enableFocus()
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
            disableFocus()
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

    // MARK: - Soustředění („Nerušit“)

    /// Zapne „Nerušit“ přes `FocusController`. `focusActive` se nastaví hned, aby
    /// `stop()` během probíhajícího zapínání vypnutí nevynechal. Požadavky se do řetězu
    /// `FocusController` řadí synchronně, takže zapnutí → vypnutí → zapnutí proběhnou
    /// přesně v tomto pořadí i při rychlém start/stop/start.
    private func enableFocus() {
        focusError = nil
        focusActive = true
        focusSession &+= 1
        let session = focusSession
        let request: Task<FocusChangeResult, Never> = FocusController.shared.enqueue(true)
        enableRequest = request
        Task { @MainActor in
            let result: FocusChangeResult = await request.value
            // Mezitím časovač skončil / začal nový – o jeho stavu rozhoduje jiný požadavek.
            guard session == self.focusSession else { return }
            if !result.ok {
                self.focusActive = false
                self.enableRequest = nil
                self.focusError = result.error ?? "Nerušit se nepodařilo zapnout"
            } else if !result.changed {
                // „Nerušit“ už bylo zapnuté uživatelem – po skončení ho nevypínat.
                self.focusActive = false
                self.enableRequest = nil
            }
        }
    }

    private func disableFocus() {
        focusActive = false
        focusSession &+= 1
        let gate: Task<FocusChangeResult, Never>? = enableRequest
        enableRequest = nil
        // Vypnout jen to, co jsme opravdu zapnuli (rozhodne se až po dokončení zapínání).
        let request: Task<FocusChangeResult, Never> = FocusController.shared.enqueue(false, onlyIfChangedBy: gate)
        Task { @MainActor in
            let result: FocusChangeResult = await request.value
            if !result.ok {
                self.focusError = result.error ?? "Nerušit se nepodařilo vypnout"
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
