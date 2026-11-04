import Foundation
import AppKit
import Combine
import SQLite3

// MARK: - Zrcadlení oznámení (experimentální)
//
// macOS nemá veřejné API pro čtení oznámení jiných aplikací. Jediná známá cesta je
// číst (pouze pro čtení!) SQLite databázi Centra oznámení, kterou spravuje `usernoted`:
//
//  • macOS 15 Sequoia a novější (vč. 26):
//      ~/Library/Group Containers/group.com.apple.usernoted/db2/db
//    (Apple ji přesunul do Group Containers – je chráněná TCC, čtení vyžaduje
//    plný přístup k disku.)
//  • macOS 14 a starší:
//      $(getconf DARWIN_USER_DIR)com.apple.notificationcenter/db2/db
//
// Schéma (ověřeno z forenzních nástrojů – plaso, mac_apt, kb-macfor):
//  • `record`: rec_id INTEGER PK, app_id, uuid, data (binární plist),
//    delivered_date REAL (sekundy od 2001-01-01), presented, style, …
//  • `app`: app_id, identifier (bundle ID, často malými písmeny)
//  • `data` → slovník; text je pod klíčem `req`: `titl`, `subt`, `body`.
//
// Styl upozornění „Žádné“: oznámení se nezobrazí jako banner, ale pokud je u aplikace
// zapnuté „Zobrazit v Centru oznámení“, usernoted ho normálně uloží do databáze –
// zrcadlo ho tedy uvidí. Pokud je „Zobrazit v Centru oznámení“ vypnuté nebo jsou
// oznámení aplikace úplně zakázaná, záznam se do databáze nedostane a NotchMax ho
// neuvidí. (Chování podle dokumentace nastavení macOS; netestováno na každé verzi.)
//
// Systémové bannery nejde programově potlačit – uživatel musí styl „Žádné“ nastavit
// sám v Nastavení systému → Oznámení.

/// Stav zrcadlení oznámení.
enum NotificationMirrorStatus: Equatable, Sendable, CustomStringConvertible {
    case disabled
    case needsFullDiskAccess
    case running
    case unsupported(String)

    var description: String {
        switch self {
        case .disabled:
            return "Vypnuto."
        case .needsFullDiskAccess:
            return "Chybí plný přístup k disku – bez něj NotchMax oznámení nepřečte."
        case .running:
            return "Běží – nová oznámení se zobrazí v notchi. Aplikace se stylem upozornění „Žádné“ musí mít zapnuté „Zobrazit v Centru oznámení“."
        case .unsupported(let reason):
            return "Nedostupné: \(reason)"
        }
    }
}

/// Jedno nové oznámení přečtené z databáze.
struct MirroredNotification: Sendable {
    let recID: Int64
    let bundleID: String
    let title: String?
    let subtitle: String?
    let body: String?
}

@MainActor
final class NotificationMirror: ObservableObject {
    typealias Status = NotificationMirrorStatus

    static let shared = NotificationMirror()

    @Published private(set) var status: Status = .disabled

    /// Plný přístup k disku (test čtením chráněného souboru). Levné – volá se i z UI.
    var hasFullDiskAccess: Bool { NotificationDBLocator.hasFullDiskAccess() }

    private let reader = NotificationDBReader()
    private var cancellables = Set<AnyCancellable>()
    private var started = false
    private var enabled = false
    /// Zvyšuje se při každém zapnutí/vypnutí – zahodí opožděná zpětná volání.
    private var generation = 0

    // Omezení: nejvýš jedno HUD za sekundu, zbytek čeká (max. 5).
    private let minInterval: TimeInterval = 1.0
    private let maxPending = 5
    private var pending: [MirroredNotification] = []
    private var lastShown: Date = .distantPast
    private var drainScheduled = false

    private var appNameCache: [String: String] = [:]
    private let ownBundleID = (Bundle.main.bundleIdentifier ?? "com.jovan.NotchMax").lowercased()

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        AppSettings.shared.$hudNotifications
            .removeDuplicates()
            .sink { [weak self] isOn in
                self?.setEnabled(isOn)
            }
            .store(in: &cancellables)
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Zapnutí / vypnutí

    private func setEnabled(_ isOn: Bool) {
        guard isOn != enabled else { return }
        enabled = isOn
        generation += 1
        pending.removeAll()

        if isOn {
            let gen = generation
            let onStatus: @Sendable (NotificationMirrorStatus) -> Void = { [weak self] newStatus in
                Task { @MainActor in
                    self?.applyStatus(newStatus, generation: gen)
                }
            }
            let onItems: @Sendable ([MirroredNotification]) -> Void = { [weak self] items in
                Task { @MainActor in
                    self?.receive(items, generation: gen)
                }
            }
            reader.start(onStatus: onStatus, onNotifications: onItems)
        } else {
            reader.stop()
            status = .disabled
        }
    }

    private func applyStatus(_ newStatus: Status, generation gen: Int) {
        guard gen == generation, enabled else { return }
        if status != newStatus { status = newStatus }
    }

    // MARK: Zobrazení

    private func receive(_ items: [MirroredNotification], generation gen: Int) {
        guard gen == generation, enabled, AppSettings.shared.hudNotifications else { return }
        for item in items where item.bundleID.lowercased() != ownBundleID {
            pending.append(item)
        }
        if pending.count > maxPending {
            pending.removeFirst(pending.count - maxPending)
        }
        drain()
    }

    private func drain() {
        guard !drainScheduled, !pending.isEmpty else { return }
        let wait = minInterval - Date().timeIntervalSince(lastShown)
        if wait > 0 {
            drainScheduled = true
            let nanos = UInt64(wait * 1_000_000_000)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: nanos)
                guard let self else { return }
                self.drainScheduled = false
                self.drain()
            }
            return
        }
        let next = pending.removeFirst()
        lastShown = Date()
        show(next)
        if !pending.isEmpty { drain() }
    }

    private func show(_ item: MirroredNotification) {
        guard enabled, AppSettings.shared.hudNotifications else { return }
        let appName = displayName(for: item.bundleID)

        var title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var bodyParts: [String] = []
        if let sub = item.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines), !sub.isEmpty {
            bodyParts.append(sub)
        }
        if let body = item.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty {
            bodyParts.append(body)
        }
        if title.isEmpty {
            if bodyParts.isEmpty { return }
            title = appName
        }
        let body: String? = bodyParts.isEmpty ? nil : bodyParts.joined(separator: " – ")

        HUDCenter.shared.show(.notification(appName: appName,
                                            bundleID: item.bundleID,
                                            title: title,
                                            body: body))
    }

    private func displayName(for bundleID: String) -> String {
        if let cached = appNameCache[bundleID] { return cached }
        var name: String?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            var display = FileManager.default.displayName(atPath: url.path)
            if display.lowercased().hasSuffix(".app") {
                display = String(display.dropLast(4))
            }
            if !display.isEmpty { name = display }
        }
        let resolved = name ?? fallbackName(for: bundleID)
        appNameCache[bundleID] = resolved
        return resolved
    }

    private func fallbackName(for bundleID: String) -> String {
        let last = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        guard let first = last.first else { return bundleID }
        return first.uppercased() + last.dropFirst()
    }
}

// MARK: - Hledání databáze a test oprávnění

enum NotificationDBLocator {
    /// Kandidátní cesty k databázi, nejpravděpodobnější první.
    static func candidatePaths() -> [String] {
        let home = NSHomeDirectory()
        let groupPath = home + "/Library/Group Containers/group.com.apple.usernoted/db2/db"
        var legacyPath: String?
        if let userDir = darwinUserDir() {
            let base = userDir.hasSuffix("/") ? userDir : userDir + "/"
            legacyPath = base + "com.apple.notificationcenter/db2/db"
        }
        if #available(macOS 15.0, *) {
            return [groupPath] + (legacyPath.map { [$0] } ?? [])
        } else {
            return (legacyPath.map { [$0] } ?? []) + [groupPath]
        }
    }

    /// `getconf DARWIN_USER_DIR` (např. /var/folders/xx/yyyy/0/).
    static func darwinUserDir() -> String? {
        let capacity = Int(PATH_MAX) + 1
        var buffer = [CChar](repeating: 0, count: capacity)
        let length = confstr(_CS_DARWIN_USER_DIR, &buffer, capacity)
        guard length > 0, length <= capacity else { return nil }
        let path = String(cString: buffer)
        return path.isEmpty ? nil : path
    }

    /// Zkusí soubor skutečně otevřít pro čtení (TCC blokuje až otevření, ne `stat`).
    static func canOpenForReading(_ path: String) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        try? handle.close()
        return true
    }

    /// Plný přístup k disku: TCC.db je čitelná jen s ním.
    static func hasFullDiskAccess() -> Bool {
        // Záměrně nesaháme na Group Containers – bez oprávnění by macOS 15+ mohl
        // opakovaně ukazovat dialog „NotchMax chce přistupovat k datům jiných aplikací“.
        let tccPath = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"
        return canOpenForReading(tccPath)
    }

    static func isGroupContainerPath(_ path: String) -> Bool {
        path.contains("/Library/Group Containers/")
    }
}

// MARK: - Čtečka databáze (vlastní sériová fronta)

private final class NotificationDBReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "cz.notchmax.notification-mirror", qos: .utility)
    private let pollInterval: TimeInterval = 1.5
    private let accessRecheckInterval: TimeInterval = 5
    /// Starší záznamy (např. po resetu rec_id) nezobrazujeme.
    private let maxAge: TimeInterval = 120
    private let batchLimit = 50

    // Stav – jen na `queue`.
    private var db: OpaquePointer?
    private var dbPath: String?
    private var lastRecID: Int64 = 0
    private var hasBaseline = false
    private var running = false
    private var timer: DispatchSourceTimer?
    private var currentInterval: TimeInterval = 0
    private var lastStatus: NotificationMirrorStatus?
    private var onStatus: (@Sendable (NotificationMirrorStatus) -> Void)?
    private var onNotifications: (@Sendable ([MirroredNotification]) -> Void)?

    func start(onStatus: @escaping @Sendable (NotificationMirrorStatus) -> Void,
               onNotifications: @escaping @Sendable ([MirroredNotification]) -> Void) {
        queue.async {
            self.onStatus = onStatus
            self.onNotifications = onNotifications
            self.running = true
            self.lastStatus = nil
            self.hasBaseline = false
            self.lastRecID = 0
            self.closeDB()
            self.tick()
        }
    }

    func stop() {
        queue.async {
            self.running = false
            self.timer?.cancel()
            self.timer = nil
            self.currentInterval = 0
            self.closeDB()
            self.hasBaseline = false
            self.onStatus = nil
            self.onNotifications = nil
        }
    }

    // MARK: Smyčka

    private func tick() {
        guard running else { return }
        if db == nil {
            let status = openDatabase()
            report(status)
        }
        if db != nil {
            poll()
        }
        schedule(interval: db != nil ? pollInterval : accessRecheckInterval)
    }

    private func schedule(interval: TimeInterval) {
        guard running else { return }
        if timer != nil && currentInterval == interval { return }
        timer?.cancel()
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(250))
        source.setEventHandler { [weak self] in
            self?.tick()
        }
        timer = source
        currentInterval = interval
        source.resume()
    }

    private func report(_ status: NotificationMirrorStatus) {
        guard status != lastStatus else { return }
        lastStatus = status
        onStatus?(status)
    }

    // MARK: Otevření

    private func openDatabase() -> NotificationMirrorStatus {
        let fm = FileManager.default
        let fullDiskAccess = NotificationDBLocator.hasFullDiskAccess()
        var candidates = NotificationDBLocator.candidatePaths()
        if !fullDiskAccess {
            // macOS 15+: aktuální databáze je jen v Group Containers (stará kopie v
            // /var/folders by byla neaktuální) → bez plného přístupu to nepůjde.
            if #available(macOS 15.0, *) { return .needsFullDiskAccess }
            // Bez plného přístupu na Group Containers nesaháme (dialog TCC by se opakoval);
            // starší umístění v /var/folders na macOS 14 může jít číst i bez něj.
            candidates = candidates.filter { !NotificationDBLocator.isGroupContainerPath($0) }
        }
        let existing = candidates.filter { fm.fileExists(atPath: $0) }

        guard !existing.isEmpty else {
            // Bez přístupu může TCC skrýt i samotnou existenci souboru.
            if !fullDiskAccess { return .needsFullDiskAccess }
            return .unsupported("databáze Centra oznámení nebyla na tomto systému nalezena.")
        }

        var lastError = ""
        var permissionProblem = false
        for path in existing {
            var handle: OpaquePointer?
            // Jen pro čtení – nikdy nezapisujeme. Bez `immutable`, aby šly vidět nové
            // zápisy usernoted (databáze běží v režimu WAL).
            let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
            let rc = sqlite3_open_v2(path, &handle, flags, nil)
            if rc != SQLITE_OK || handle == nil {
                lastError = errorMessage(handle, code: rc)
                if isPermissionError(rc) { permissionProblem = true }
                if handle != nil { sqlite3_close(handle) }
                continue
            }
            sqlite3_busy_timeout(handle, 400)

            // Ověření čtením + výchozí bod (staré záznamy nezobrazujeme).
            switch queryMaxRecID(handle) {
            case .success(let maxID):
                db = handle
                dbPath = path
                if !hasBaseline {
                    lastRecID = maxID
                    hasBaseline = true
                }
                return .running
            case .failure(let code, let message):
                lastError = message
                if isPermissionError(code) { permissionProblem = true }
                sqlite3_close(handle)
            }
        }

        if permissionProblem || !fullDiskAccess {
            return .needsFullDiskAccess
        }
        return .unsupported("databázi oznámení nelze přečíst (\(lastError)).")
    }

    private func closeDB() {
        if let db { sqlite3_close(db) }
        db = nil
        dbPath = nil
    }

    private func isPermissionError(_ code: Int32) -> Bool {
        let primary = code & 0xFF
        return primary == SQLITE_CANTOPEN || primary == SQLITE_PERM || primary == SQLITE_AUTH
    }

    private func errorMessage(_ handle: OpaquePointer?, code: Int32) -> String {
        if let handle, let cString = sqlite3_errmsg(handle) {
            return String(cString: cString)
        }
        if let cString = sqlite3_errstr(code) {
            return String(cString: cString)
        }
        return "chyba \(code)"
    }

    // MARK: Dotazy

    private enum MaxResult {
        case success(Int64)
        case failure(Int32, String)
    }

    private func queryMaxRecID(_ handle: OpaquePointer?) -> MaxResult {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, "SELECT IFNULL(MAX(rec_id), 0) FROM record", -1, &stmt, nil)
        guard rc == SQLITE_OK, stmt != nil else {
            let message = errorMessage(handle, code: rc)
            sqlite3_finalize(stmt)
            return .failure(rc, message)
        }
        defer { sqlite3_finalize(stmt) }
        let step = sqlite3_step(stmt)
        if step == SQLITE_ROW {
            return .success(sqlite3_column_int64(stmt, 0))
        }
        if step == SQLITE_DONE {
            return .success(0)
        }
        return .failure(step, errorMessage(handle, code: step))
    }

    private func poll() {
        guard let handle = db else { return }

        // rec_id může po smazání posledních záznamů klesnout – srovnáme výchozí bod.
        switch queryMaxRecID(handle) {
        case .success(let maxID):
            if maxID < lastRecID { lastRecID = maxID }
            if maxID == lastRecID { return }
        case .failure(let code, let message):
            handleQueryFailure(code: code, message: message)
            return
        }

        let sql = """
            SELECT r.rec_id, a.identifier, r.data, r.delivered_date
            FROM record r JOIN app a ON r.app_id = a.app_id
            WHERE r.rec_id > ?
            ORDER BY r.rec_id
            LIMIT \(batchLimit)
            """
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, stmt != nil else {
            let message = errorMessage(handle, code: rc)
            sqlite3_finalize(stmt)
            handleQueryFailure(code: rc, message: message)
            return
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, lastRecID)

        let now = Date()
        var items: [MirroredNotification] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                if step != SQLITE_BUSY && step != SQLITE_LOCKED {
                    handleQueryFailure(code: step, message: errorMessage(handle, code: step))
                }
                break
            }

            let recID = sqlite3_column_int64(stmt, 0)
            if recID > lastRecID { lastRecID = recID }

            guard let identPtr = sqlite3_column_text(stmt, 1) else { continue }
            let bundleID = String(cString: identPtr)

            if sqlite3_column_type(stmt, 3) != SQLITE_NULL {
                let delivered = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(stmt, 3))
                if now.timeIntervalSince(delivered) > maxAge { continue }
            }

            let length = Int(sqlite3_column_bytes(stmt, 2))
            guard length > 0, let blob = sqlite3_column_blob(stmt, 2) else { continue }
            let data = Data(bytes: blob, count: length)
            guard let item = decode(data, recID: recID, bundleID: bundleID) else { continue }
            items.append(item)
        }

        if !items.isEmpty {
            onNotifications?(items)
        }
    }

    private func handleQueryFailure(code: Int32, message: String) {
        let primary = code & 0xFF
        // Zaneprázdněná databáze – zkusíme to příště.
        if primary == SQLITE_BUSY || primary == SQLITE_LOCKED { return }
        closeDB()
        if isPermissionError(code) || !NotificationDBLocator.hasFullDiskAccess() {
            report(.needsFullDiskAccess)
        } else {
            report(.unsupported("chyba čtení databáze oznámení (\(message))."))
        }
    }

    // MARK: Dekódování plistu

    private func decode(_ data: Data, recID: Int64, bundleID: String) -> MirroredNotification? {
        guard let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let root = object as? [String: Any] else { return nil }
        let req = (root["req"] as? [String: Any]) ?? root

        let title = string(req, "titl") ?? string(req, "title")
        let subtitle = string(req, "subt") ?? string(req, "subtitle")
        let body = string(req, "body")

        if title == nil && subtitle == nil && body == nil { return nil }
        let app = (root["app"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? bundleID
        return MirroredNotification(recID: recID, bundleID: app, title: title, subtitle: subtitle, body: body)
    }

    private func string(_ dict: [String: Any], _ key: String) -> String? {
        guard let value = dict[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
