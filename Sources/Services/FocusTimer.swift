import AppKit
import IOKit.pwr_mgt

/// Focus časovač + „nenechat Mac usnout“.
@MainActor
final class FocusTimer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var remaining: TimeInterval = 0
    @Published private(set) var total: TimeInterval = 0
    @Published var keepAwake = false {
        didSet { updateAssertion() }
    }

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
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        endDate = nil
        isRunning = false
        remaining = 0
        total = 0
    }

    private func tick() {
        guard let end = endDate else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        if remaining <= 0 {
            stop()
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
    }

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
