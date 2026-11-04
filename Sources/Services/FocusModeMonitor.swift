import Foundation
import Combine

/// Stav režimu Soustředění přečtený z ~/Library/DoNotDisturb/DB.
struct FocusSnapshot: Sendable, Equatable {
    /// false = soubory nejdou číst (chybí Plný přístup k disku).
    var canRead: Bool
    /// Identifikátor aktivního režimu, nil = vypnuto.
    var modeID: String?
    var name: String?
    var symbol: String?
}

/// Sleduje změny režimu Soustředění (macOS 12+) a ukazuje v notchi krátký HUD.
/// Čte `Assertions.json` a `ModeConfigurations.json` – vyžaduje Plný přístup k disku.
@MainActor
final class FocusModeMonitor: ObservableObject {
    static let shared = FocusModeMonitor()

    /// Název aktivního režimu (nil = vypnuto nebo neznámé).
    @Published private(set) var activeModeName: String?
    /// Zda jdou soubory se stavem Soustředění číst (jinak je potřeba Plný přístup k disku).
    @Published private(set) var canRead: Bool = true

    private var watcher: FocusFileWatcher?
    private var observer: NSObjectProtocol?
    /// Poslední čitelný stav; nil = zatím žádný (první stav se jen uloží, bez HUD).
    private var last: FocusSnapshot?

    private init() {}

    func start() {
        guard watcher == nil else { return }
        let w = FocusFileWatcher { snapshot in
            Task { @MainActor in
                FocusModeMonitor.shared.apply(snapshot)
            }
        }
        watcher = w

        // Nedokumentovaná notifikace – pokud chodí, jen urychlí načtení.
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.donotdisturb.state.changed"),
            object: nil,
            queue: .main
        ) { _ in
            w.poke()
        }

        w.start()
    }

    private func apply(_ snapshot: FocusSnapshot) {
        if canRead != snapshot.canRead { canRead = snapshot.canRead }
        guard snapshot.canRead else { return }

        let newName: String? = snapshot.modeID == nil ? nil : snapshot.name
        if activeModeName != newName { activeModeName = newName }

        guard let previous = last else {
            // Výchozí stav při startu (nebo po udělení přístupu) – bez HUD.
            last = snapshot
            return
        }
        last = snapshot

        guard previous.modeID != snapshot.modeID else { return }
        guard AppSettings.shared.hudFocus else { return }

        if snapshot.modeID != nil {
            HUDCenter.shared.show(.focus(
                name: snapshot.name ?? "Soustředění",
                symbol: snapshot.symbol ?? "moon.fill",
                enabled: true
            ))
        } else {
            HUDCenter.shared.show(.focus(
                name: previous.name ?? "Soustředění",
                symbol: previous.symbol ?? "moon.fill",
                enabled: false
            ))
        }
    }
}

// MARK: - Sledování souborů (vše na vlastní sériové frontě)

final class FocusFileWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "NotchMax.FocusFileWatcher", qos: .utility)
    private let dbDirectory: URL
    private let onSnapshot: @Sendable (FocusSnapshot) -> Void

    // Následující stav je přístupný jen z `queue`.
    private var directorySource: DispatchSourceFileSystemObject?
    private var pollTimer: DispatchSourceTimer?
    private var pendingRead: DispatchWorkItem?
    private var lastEmitted: FocusSnapshot?

    init(onSnapshot: @escaping @Sendable (FocusSnapshot) -> Void) {
        self.onSnapshot = onSnapshot
        self.dbDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB", isDirectory: true)
    }

    func start() {
        queue.async { [self] in
            openDirectoryWatch()
            startPolling()
            readNow()
        }
    }

    /// Vynutí brzké znovunačtení (např. po distribuované notifikaci).
    func poke() {
        queue.async { [self] in scheduleRead() }
    }

    private func openDirectoryWatch() {
        guard directorySource == nil else { return }
        let fd = open(dbDirectory.path, O_EVTONLY)
        guard fd >= 0 else { return } // chybí složka nebo přístup – zůstává polling

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .extend, .attrib, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            guard let self, let src = self.directorySource else { return }
            let flags = src.data
            if flags.contains(.delete) || flags.contains(.rename) {
                // Složka byla nahrazena – zavřít, při dalším čtení se otevře znovu.
                self.closeDirectoryWatch()
            }
            self.scheduleRead()
        }
        source.setCancelHandler {
            close(fd)
        }
        directorySource = source
        source.resume()
    }

    private func closeDirectoryWatch() {
        directorySource?.cancel()
        directorySource = nil
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 3, repeating: 3, leeway: .milliseconds(500))
        timer.setEventHandler { [weak self] in
            self?.readNow()
        }
        pollTimer = timer
        timer.resume()
    }

    /// Debounce – soubory se zapisují v několika krocích.
    private func scheduleRead() {
        pendingRead?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.readNow()
        }
        pendingRead = item
        queue.asyncAfter(deadline: .now() + 0.25, execute: item)
    }

    private func readNow() {
        if directorySource == nil { openDirectoryWatch() }
        let snapshot = FocusFileWatcher.readSnapshot(directory: dbDirectory)
        guard snapshot != lastEmitted else { return }
        lastEmitted = snapshot
        onSnapshot(snapshot)
    }

    // MARK: - Čtení JSON

    private static func isMissingFileError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain,
           ns.code == NSFileReadNoSuchFileError || ns.code == NSFileNoSuchFileError {
            return true
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError,
           underlying.domain == NSPOSIXErrorDomain, underlying.code == Int(ENOENT) {
            return true
        }
        return false
    }

    static func readSnapshot(directory: URL) -> FocusSnapshot {
        let fm = FileManager.default
        do {
            _ = try fm.contentsOfDirectory(atPath: directory.path)
        } catch {
            // Složka neexistuje = Soustředění nikdy nepoužito → čitelné, vypnuto.
            if isMissingFileError(error) {
                return FocusSnapshot(canRead: true, modeID: nil, name: nil, symbol: nil)
            }
            return FocusSnapshot(canRead: false, modeID: nil, name: nil, symbol: nil)
        }

        let assertionsURL = directory.appendingPathComponent("Assertions.json")
        let assertionsData: Data
        do {
            assertionsData = try Data(contentsOf: assertionsURL)
        } catch {
            if isMissingFileError(error) {
                return FocusSnapshot(canRead: true, modeID: nil, name: nil, symbol: nil)
            }
            return FocusSnapshot(canRead: false, modeID: nil, name: nil, symbol: nil)
        }

        guard let modeID = activeModeID(from: assertionsData) else {
            return FocusSnapshot(canRead: true, modeID: nil, name: nil, symbol: nil)
        }

        let configURL = directory.appendingPathComponent("ModeConfigurations.json")
        let config = (try? Data(contentsOf: configURL)).flatMap { modeConfig(from: $0, modeID: modeID) }
        let defaults = defaultInfo(for: modeID)

        let name: String
        if defaults.builtIn {
            name = defaults.name
        } else if let n = config?.name, !n.isEmpty {
            name = n
        } else {
            name = defaults.name
        }

        let symbol: String
        if let s = config?.symbol, !s.isEmpty {
            symbol = s
        } else {
            symbol = defaults.symbol
        }

        return FocusSnapshot(canRead: true, modeID: modeID, name: name, symbol: symbol)
    }

    /// `data[].storeAssertionRecords[].assertionDetails.assertionDetailsModeIdentifier` – poslední vyhrává.
    private static func activeModeID(from data: Data) -> String? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entries = root["data"] as? [[String: Any]] else { return nil }
        var result: String?
        for entry in entries {
            guard let records = entry["storeAssertionRecords"] as? [[String: Any]] else { continue }
            for record in records {
                guard let details = record["assertionDetails"] as? [String: Any],
                      let id = details["assertionDetailsModeIdentifier"] as? String,
                      !id.isEmpty else { continue }
                result = id
            }
        }
        return result
    }

    /// `data[].modeConfigurations[<id>].mode` → (name, symbolImageName)
    private static func modeConfig(from data: Data, modeID: String) -> (name: String?, symbol: String?)? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entries = root["data"] as? [[String: Any]] else { return nil }
        for entry in entries {
            guard let configs = entry["modeConfigurations"] as? [String: Any],
                  let config = configs[modeID] as? [String: Any],
                  let mode = config["mode"] as? [String: Any] else { continue }
            return (mode["name"] as? String, mode["symbolImageName"] as? String)
        }
        return nil
    }

    /// České názvy a symboly vestavěných režimů.
    private static func defaultInfo(for modeID: String) -> (name: String, symbol: String, builtIn: Bool) {
        let id = modeID.lowercased()
        if id == "com.apple.donotdisturb.mode.default" || id.hasSuffix("mode.default") {
            return ("Nerušit", "moon.fill", true)
        }
        if id.contains("reduce-interruptions") || id.contains("reduceinterruptions") {
            return ("Omezit vyrušování", "sparkles", true)
        }
        if id.hasPrefix("com.apple.") {
            if id.contains("work") { return ("Práce", "briefcase.fill", true) }
            if id.contains("personal") { return ("Osobní", "person.fill", true) }
            if id.contains("sleep") { return ("Spánek", "bed.double.fill", true) }
            if id.contains("driving") { return ("Řízení", "car.fill", true) }
        }
        return ("Soustředění", "moon.fill", false)
    }
}
