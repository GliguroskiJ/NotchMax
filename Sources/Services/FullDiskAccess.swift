import Foundation

/// Zjištění plného přístupu k disku (Full Disk Access, TCC `kTCCServiceSystemPolicyAllFiles`).
///
/// macOS nemá veřejné API, které by se dalo zeptat přímo. Zkoušíme proto skutečné čtení
/// několika míst chráněných TCC (TCC blokuje až otevření/čtení, ne `stat`):
///  • EPERM / EACCES → přístup odepřen,
///  • úspěšné čtení → přístup udělen,
///  • soubor neexistuje → nelze rozhodnout, zkusí se další místo.
///
/// Výsledek se ukládá na 2 s, takže `isGranted` je levné volat i z UI (z libovolného vlákna).
enum FullDiskAccess {
    /// Výsledek zkoušky plného přístupu k disku.
    enum Probe: Sendable, Equatable {
        /// Aspoň jedno chráněné místo šlo přečíst.
        case granted
        /// Chráněná místa existují, ale macOS čtení odmítl (EPERM/EACCES).
        case denied
        /// Nic z testovaných míst neexistuje – nelze rozhodnout.
        case unknown
    }

    /// Plný přístup k disku potvrzený skutečným čtením (výsledek uložen na 2 s).
    static var isGranted: Bool {
        probe() == .granted
    }

    /// Stav pro diagnostiku („granted“ / „denied“ / „unknown“).
    static var statusDescription: String {
        switch probe() {
        case .granted: return "granted"
        case .denied: return "denied"
        case .unknown: return "unknown"
        }
    }

    /// Vrátí (případně uložený) výsledek zkoušky.
    static func probe() -> Probe {
        cacheLock.lock()
        if let cached = cachedProbe, Date().timeIntervalSince(cachedAt) < cacheLifetime {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let result = probeNow()

        cacheLock.lock()
        cachedProbe = result
        cachedAt = Date()
        cacheLock.unlock()
        return result
    }

    /// Zahodí uložený výsledek (např. po návratu z Nastavení systému).
    static func invalidateCache() {
        cacheLock.lock()
        cachedProbe = nil
        cacheLock.unlock()
    }

    // MARK: - Interní

    private static let cacheLifetime: TimeInterval = 2
    private static let cacheLock = NSLock()
    // Přístup jen pod `cacheLock`.
    private static var cachedProbe: Probe?
    private static var cachedAt: Date = .distantPast

    /// Zkouší skutečné čtení několika míst chráněných TCC.
    /// (Samotná ~/Library/…/TCC.db nestačí: na novějších macOS může být nečitelná
    /// i s plným přístupem, nebo naopak chybět.)
    private static func probeNow() -> Probe {
        let home = NSHomeDirectory()
        let files = [
            home + "/Library/Safari/Bookmarks.plist",
            home + "/Library/Safari/History.db",
            home + "/Library/Application Support/com.apple.TCC/TCC.db",
            "/Library/Application Support/com.apple.TCC/TCC.db",
        ]
        let directories = [
            home + "/Library/Safari",
            home + "/Library/Mail",
            home + "/Library/Messages",
        ]

        var sawDenied = false
        for path in files {
            switch probeFile(path) {
            case .granted: return .granted
            case .denied: sawDenied = true
            case .unknown: break
            }
        }
        for path in directories {
            switch probeDirectory(path) {
            case .granted: return .granted
            case .denied: sawDenied = true
            case .unknown: break
            }
        }
        return sawDenied ? .denied : .unknown
    }

    /// Otevře soubor a přečte 1 bajt.
    private static func probeFile(_ path: String) -> Probe {
        let fd = Darwin.open(path, O_RDONLY | O_NONBLOCK)
        if fd < 0 {
            return classify(errno)
        }
        var byte: UInt8 = 0
        let count = Darwin.read(fd, &byte, 1)
        let readError = errno
        Darwin.close(fd)
        if count >= 0 { return .granted }
        return classify(readError)
    }

    /// Otevře adresář a přečte první položku.
    private static func probeDirectory(_ path: String) -> Probe {
        guard let dir = opendir(path) else {
            return classify(errno)
        }
        defer { closedir(dir) }
        errno = 0
        if readdir(dir) != nil { return .granted }
        let error = errno
        return error == 0 ? .granted : classify(error)
    }

    private static func classify(_ error: Int32) -> Probe {
        switch error {
        case EPERM, EACCES: return .denied
        default: return .unknown // ENOENT, ENOTDIR, …
        }
    }
}
