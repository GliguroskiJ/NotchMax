import AppKit

enum MediaSource {
    case music, spotify

    var bundleID: String {
        switch self {
        case .music: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        }
    }

    var appName: String {
        switch self {
        case .music: return "Music"
        case .spotify: return "Spotify"
        }
    }
}

/// Sleduje Apple Music a Spotify přes distribuované notifikace (bez pollingu)
/// a ovládá je přes AppleScript. Soukromé MediaRemote API se záměrně nepoužívá.
@MainActor
final class MediaMonitor: NSObject, ObservableObject {
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var artwork: NSImage?
    @Published private(set) var isPlaying = false
    @Published private(set) var source: MediaSource?

    var hasTrack: Bool { !title.isEmpty }

    override init() {
        super.init()
        let center = DistributedNotificationCenter.default()
        center.addObserver(self, selector: #selector(musicChanged(_:)),
                           name: Notification.Name("com.apple.Music.playerInfo"), object: nil,
                           suspensionBehavior: .deliverImmediately)
        center.addObserver(self, selector: #selector(spotifyChanged(_:)),
                           name: Notification.Name("com.spotify.client.PlaybackStateChanged"), object: nil,
                           suspensionBehavior: .deliverImmediately)
        // Přehrávač skončil bez události „Stopped“ → smazat zastaralý stav.
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil
        )
        pollInitialState()
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let src = source, app.bundleIdentifier == src.bundleID else { return }
        clear()
    }

    // MARK: - Notifikace

    @objc private func musicChanged(_ note: Notification) {
        handle(note.userInfo, from: .music)
    }

    @objc private func spotifyChanged(_ note: Notification) {
        handle(note.userInfo, from: .spotify)
    }

    private func handle(_ info: [AnyHashable: Any]?, from src: MediaSource) {
        guard let info else { return }
        let state = (info["Player State"] as? String ?? "").lowercased()
        if state == "stopped" {
            if source == src { clear() }
            return
        }
        let name = info["Name"] as? String ?? ""
        let changed = name != title || source != src
        source = src
        title = name
        artist = info["Artist"] as? String ?? ""
        album = info["Album"] as? String ?? ""
        isPlaying = state == "playing"
        if changed {
            artwork = nil
            fetchArtwork(for: src, expectedTitle: name)
        }
    }

    private func clear() {
        title = ""
        artist = ""
        album = ""
        artwork = nil
        isPlaying = false
        source = nil
    }

    // MARK: - Počáteční stav (jen pro běžící přehrávače)

    private func isRunning(_ src: MediaSource) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: src.bundleID).isEmpty
    }

    private func pollInitialState() {
        for src in [MediaSource.spotify, .music] where isRunning(src) {
            let script = "tell application \"\(src.appName)\" to return (player state as string) & \"|\" & (name of current track) & \"|\" & (artist of current track)"
            guard let text = run(script)?.stringValue else { continue }
            let parts = text.components(separatedBy: "|")
            guard parts.count >= 3 else { continue }
            let state = parts[0].lowercased()
            guard state == "playing" || state == "paused" else { continue }
            source = src
            title = parts[1]
            artist = parts[2]
            isPlaying = state == "playing"
            fetchArtwork(for: src, expectedTitle: parts[1])
        }
    }

    // MARK: - Obal alba

    private func fetchArtwork(for src: MediaSource, expectedTitle: String) {
        Task { [weak self] in
            // Přehrávač potřebuje chvíli, než aktualizuje „current track“.
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, self.title == expectedTitle, self.isRunning(src) else { return }
            switch src {
            case .spotify:
                guard let urlString = self.run("tell application \"Spotify\" to return artwork url of current track")?.stringValue,
                      let url = URL(string: urlString),
                      let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = NSImage(data: data),
                      self.title == expectedTitle else { return }
                self.artwork = image
            case .music:
                guard let descriptor = self.run("tell application \"Music\" to return raw data of artwork 1 of current track"),
                      let image = NSImage(data: descriptor.data) else { return }
                self.artwork = image
            }
        }
    }

    // MARK: - Ovládání

    func togglePlayPause() { command("playpause") }
    func next() { command("next track") }
    func previous() { command("previous track") }

    private func command(_ verb: String) {
        guard let src = source, isRunning(src) else { return }
        _ = run("tell application \"\(src.appName)\" to \(verb)")
    }

    /// NSAppleScript se spouští na hlavním vlákně (Apple ho nepovažuje za thread-safe).
    private func run(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }
}
