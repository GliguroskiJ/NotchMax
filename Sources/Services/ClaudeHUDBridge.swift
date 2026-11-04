import Foundation
import Combine

/// Propojí `ClaudeMonitor` s HUD v notchi: když agent Claude Code dokončí práci
/// nebo čeká na vstup, notch krátce blikne.
@MainActor
final class ClaudeHUDBridge: ObservableObject {
    static let shared = ClaudeHUDBridge()

    private var cancellables = Set<AnyCancellable>()
    private var lastShownDate: Date?
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        // Událost, která existuje už při startu, nezobrazujeme (není „nová“).
        lastShownDate = ClaudeMonitor.shared.lastEvent?.date

        ClaudeMonitor.shared.$lastEvent
            .compactMap { $0 }
            // `lastEvent` se nastavuje dřív než `sessions` (ve stejném průchodu) –
            // asynchronní doručení zajistí, že už čteme aktuální relace.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handle(event)
            }
            .store(in: &cancellables)
    }

    private func handle(_ event: ClaudeEvent) {
        if let lastShownDate, event.date <= lastShownDate { return }
        lastShownDate = event.date

        guard AppSettings.shared.hudClaude else { return }

        let needsAttention = event.kind == .needsAttention
        var message: String?
        if needsAttention {
            let session = ClaudeMonitor.shared.sessions.first {
                $0.projectName == event.sessionName && $0.state == .waiting && $0.attentionMessage != nil
            } ?? ClaudeMonitor.shared.sessions.first {
                $0.projectName == event.sessionName && $0.attentionMessage != nil
            }
            if let text = session?.attentionMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                message = text
            }
        }

        HUDCenter.shared.show(.claude(project: event.sessionName,
                                      needsAttention: needsAttention,
                                      message: message))
    }
}
