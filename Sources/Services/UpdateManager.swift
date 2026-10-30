import AppKit
import Sparkle

/// Aktualizace přes Sparkle 2: appcast.xml leží u GitHub Release, update se vždy
/// instaluje až po potvrzení uživatelem (standardní dialog Sparkle).
/// Plánované kontroly (interval 24 h) řídí Sparkle sám přes Info.plist;
/// tady přibývá kontrola při startu a po probuzení Macu.
@MainActor
final class UpdateManager: NSObject, ObservableObject {
    private var controller: SPUStandardUpdaterController!
    private var lastBackgroundCheck = Date.distantPast

    var updater: SPUUpdater { controller.updater }

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )
        // Kontrola při startu (s odstupem, aby se stihla zvednout síť)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            self?.checkInBackground()
        }
    }

    // MARK: - Kontroly

    @objc private func didWake() {
        guard Date().timeIntervalSince(lastBackgroundCheck) > 3600 else { return }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            self?.checkInBackground()
        }
    }

    private func checkInBackground() {
        guard updater.automaticallyChecksForUpdates else { return }
        lastBackgroundCheck = Date()
        updater.checkForUpdatesInBackground()
    }

    /// Tlačítko „Zkontrolovat aktualizace…“
    func checkNow() {
        controller.checkForUpdates(nil)
    }

    var automaticChecks: Bool {
        get { updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            updater.automaticallyChecksForUpdates = newValue
        }
    }

    var lastCheckDate: Date? { updater.lastUpdateCheckDate }
}
