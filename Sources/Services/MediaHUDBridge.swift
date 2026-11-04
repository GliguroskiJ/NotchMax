import AppKit
import Combine

/// Převádí změny přehrávání (MediaMonitor) a stisky mediálních kláves (MediaKeyInterceptor)
/// na krátké HUD animace v notchi (play / pauza / další / předchozí).
@MainActor
final class MediaHUDBridge {
    static let shared = MediaHUDBridge()

    /// Po startu ignorovat události z počátečního načtení stavu přehrávačů.
    private static let startupGrace: TimeInterval = 2.0
    /// Stejná akce se stejným titulem nejvýš jednou za tento interval (Spotify/Music posílají duplicitní notifikace).
    private static let debounce: TimeInterval = 0.6
    /// Jak dlouho po stisku „předchozí“ se změna titulu považuje za předchozí skladbu.
    private static let previousWindow: TimeInterval = 1.5
    /// Za jak dlouho po stisku play/pauzy dořešit HUD, pokud nepřišla změna stavu.
    /// (Spotify posílá notifikaci se zpožděním – při kratší době fallback ukázal starý stav a hned po něm nový.)
    private static let toggleFallbackDelay: TimeInterval = 0.8
    /// Po přeskočení skladby přehrávače krátce hlásí pauza → přehrávání; to se jako play/pauza neukazuje.
    private static let skipQuietWindow: TimeInterval = 1.2

    private var cancellables = Set<AnyCancellable>()
    private var started = false
    private var startedAt = Date.distantFuture

    private var lastTitle = ""
    private var lastIsPlaying = false
    private var lastPreviousKey = Date.distantPast
    private var lastToggleKey = Date.distantPast
    private var lastSkipKey = Date.distantPast
    private var lastPlayPauseShown = Date.distantPast
    private var lastShown: [String: Date] = [:]
    private var toggleTask: Task<Void, Never>?

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        startedAt = Date()
        let media = AppServices.shared.media
        lastTitle = media.title
        lastIsPlaying = media.isPlaying

        // receive(on:) → hodnoty zpracujeme až po dokončení aktualizace MediaMonitoru
        // (title i isPlaying jsou pak už oba nastavené).
        media.$isPlaying
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] playing in self?.playingChanged(playing) }
            .store(in: &cancellables)

        media.$title
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] title in self?.titleChanged(title) }
            .store(in: &cancellables)
    }

    // MARK: - Mediální klávesy

    /// Volá MediaKeyInterceptor při stisku mediální klávesy. `.play` znamená přepnutí play/pauza.
    func mediaKeyPressed(_ action: MediaAction) {
        let media = AppServices.shared.media
        switch action {
        case .play, .pause:
            lastToggleKey = Date()
            toggleTask?.cancel()
            let pressedAt = lastToggleKey
            toggleTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.toggleFallbackDelay * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                // Změna stavu už HUD ukázala → nic.
                guard self.lastPlayPauseShown < pressedAt else { return }
                let m = AppServices.shared.media
                guard m.hasTrack else { return }
                self.emit(m.isPlaying ? .play : .pause, title: m.title, artist: m.artist, ignoreGrace: true)
            }
        case .next, .previous:
            lastSkipKey = Date()
            if action == .previous { lastPreviousKey = lastSkipKey }
            // Okamžitá odezva s aktuálním titulem; změna titulu ji pak nahradí novou skladbou.
            guard media.hasTrack else { return }
            emit(action, title: media.title, artist: media.artist, ignoreGrace: true)
        }
    }

    // MARK: - Změny přehrávání

    private func playingChanged(_ playing: Bool) {
        defer { lastIsPlaying = playing }
        guard playing != lastIsPlaying else { return }
        let media = AppServices.shared.media
        // Vymazání stavu (přehrávač ukončen) není pauza.
        guard media.hasTrack else { return }
        // Přechodný stav během přeskočení skladby (ne když uživatel právě mačkal play/pauzu).
        if Date().timeIntervalSince(lastSkipKey) < Self.skipQuietWindow,
           lastToggleKey < lastSkipKey { return }
        emit(playing ? .play : .pause, title: media.title, artist: media.artist, ignoreGrace: false)
    }

    private func titleChanged(_ title: String) {
        let previous = lastTitle
        lastTitle = title
        guard title != previous, !title.isEmpty, !previous.isEmpty else { return }
        let media = AppServices.shared.media
        guard media.isPlaying else { return }
        let isPrevious = Date().timeIntervalSince(lastPreviousKey) < Self.previousWindow
        emit(isPrevious ? .previous : .next, title: title, artist: media.artist, ignoreGrace: false)
    }

    // MARK: - Výstup

    private func emit(_ action: MediaAction, title: String?, artist: String?, ignoreGrace: Bool) {
        guard AppSettings.shared.hudMedia else { return }
        if !ignoreGrace, Date().timeIntervalSince(startedAt) < Self.startupGrace { return }
        // Otevřený panel už přehrávání ukazuje.
        if AppServices.shared.viewModel?.isOpen == true { return }

        let now = Date()
        let key = "\(action)|\(title ?? "")"
        if let last = lastShown[key], now.timeIntervalSince(last) < Self.debounce { return }
        lastShown[key] = now
        if lastShown.count > 32 {
            lastShown = lastShown.filter { now.timeIntervalSince($0.value) < Self.debounce }
        }
        if action == .play || action == .pause {
            lastPlayPauseShown = now
            toggleTask?.cancel()
        }

        let t = (title?.isEmpty ?? true) ? nil : title
        let a = (artist?.isEmpty ?? true) ? nil : artist
        HUDCenter.shared.show(.media(action: action, title: t, artist: a))
    }
}
