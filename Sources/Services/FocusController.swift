import AppKit
import ApplicationServices
import Combine
import Darwin

/// Výsledek přepnutí režimu „Nerušit“.
struct FocusChangeResult: Sendable {
    /// Požadovaný stav se podařilo nastavit (nebo už byl nastaven).
    let ok: Bool
    /// `true`, pokud se stav opravdu změnil (false = už byl v požadovaném stavu).
    let changed: Bool
    /// Strategie, která uspěla (prázdné při neúspěchu). Český klíč – UI ho překládá přes `L(…)`.
    let method: String
    /// Chyba (už přeložená přes `L(…)`).
    let error: String?
}

/// Záznam průběhu jednoho pokusu (vláknově bezpečný – strategie běží mimo hlavní vlákno).
final class FocusAttemptLog: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    private let started = Date()

    func add(_ line: String) {
        let stamp = String(format: "+%.2fs", Date().timeIntervalSince(started))
        lock.lock()
        lines.append(stamp + " " + line)
        lock.unlock()
        NSLog("NotchMax Focus: %@", line)
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return lines.isEmpty ? "(empty)" : lines.joined(separator: "\n")
    }
}

/// Zapíná/vypíná macOS „Nerušit“ (Soustředění) bez Apple Zkratek.
///
/// Veřejné API pro nastavení Focusu neexistuje. Strategie v pořadí:
///  1. Systémová klávesová zkratka „Zapnout/vypnout Nerušit“ (symbolická zkratka č. 175
///     v `com.apple.symbolichotkeys`). Když není nastavená, NotchMax zapíše ⌃⌥⌘D, aktivuje ji
///     a stiskne přes CGEvent. Je to přepínač → stav se nejdřív čte z ~/Library/DoNotDisturb/DB
///     (stejný zdroj jako `FocusModeMonitor`), stiskne se jen v případě potřeby a výsledek se ověří.
///  2. Zpřístupnění (AXUIElement) – menu bar Soustředění / Ovládací centrum → modul Soustředění.
///  3. Soukromý DoNotDisturb.framework (`DNDModeAssertionService`) – daemon ho u aplikací
///     bez interního entitlementu obvykle odmítne; jen záloha.
/// Každý úspěch se (pokud jde stav číst) ověřuje ze souborů Soustředění.
@MainActor
final class FocusController: ObservableObject {
    static let shared = FocusController()

    @Published var lastError: String?
    /// Strategie, která naposledy uspěla (český klíč – UI ho překládá přes `L(…)`).
    @Published private(set) var method: String = ""
    /// Chybí oprávnění Zpřístupnění (zkratka i Ovládací centrum bez něj nefungují).
    @Published private(set) var needsAccessibility: Bool = !AXIsProcessTrusted()
    @Published private(set) var isBusy = false

    private enum Strategy: String, CaseIterable {
        case hotkey
        case accessibility
        case privateFramework
    }

    static let methodHotkey = "Klávesová zkratka Nerušit"
    static let methodAccessibility = "Ovládací centrum (Zpřístupnění)"
    static let methodPrivate = "DoNotDisturb.framework"

    /// Řetěz požadavků – volání se provádějí postupně, nikdy souběžně.
    private var chain: Task<FocusChangeResult, Never>?
    /// Strategie, kterou se „Nerušit“ naposledy zapnulo (pro vypnutí se zkusí první).
    private var lastOnStrategy: Strategy?
    /// Soukromé API už jednou selhalo – v této relaci se nezkouší znovu.
    private var privateUnavailable = false
    /// Poslední záznam pokusu pro každou strategii (pro diagnostiku).
    private var lastAttemptLogs: [String: String] = [:]

    private init() {}

    /// Znovu načte stav oprávnění Zpřístupnění.
    func refreshPermission() {
        let needs = !AXIsProcessTrusted()
        if needs != needsAccessibility { needsAccessibility = needs }
    }

    /// Zapne / vypne „Nerušit“. Vrací `true`, pokud je po volání v požadovaném stavu.
    @discardableResult
    func setDoNotDisturb(_ on: Bool) async -> Bool {
        let result = await apply(on)
        return result.ok
    }

    /// Jako `setDoNotDisturb`, ale s informací, zda se stav opravdu změnil.
    func apply(_ on: Bool) async -> FocusChangeResult {
        await enqueue(on).value
    }

    /// Synchronně zařadí požadavek na konec řetězu (pořadí = pořadí volání).
    /// `gate`: dřívější požadavek z řetězu – tento se provede jen tehdy, když `gate`
    /// „Nerušit“ opravdu přepnul (jinak vrátí ok bez změny).
    @discardableResult
    func enqueue(_ on: Bool, onlyIfChangedBy gate: Task<FocusChangeResult, Never>? = nil) -> Task<FocusChangeResult, Never> {
        let previous = chain
        let task = Task<FocusChangeResult, Never> { @MainActor in
            _ = await previous?.value
            if let gate {
                let gateResult: FocusChangeResult = await gate.value
                guard gateResult.ok && gateResult.changed else {
                    return FocusChangeResult(ok: true, changed: false, method: "", error: nil)
                }
            }
            return await self.perform(on)
        }
        chain = task
        return task
    }

    // MARK: - Provedení

    private func perform(_ on: Bool) async -> FocusChangeResult {
        refreshPermission()
        isBusy = true
        defer { isBusy = false }

        // Vypnutí přes soukromé API ruší jen vlastní aserce NotchMaxu, takže má smysl
        // jen tehdy, když jsme jím „Nerušit“ i zapnuli.
        let order: [Strategy]
        if on {
            order = [.hotkey, .accessibility, .privateFramework]
        } else if lastOnStrategy == .privateFramework {
            order = [.privateFramework, .hotkey, .accessibility]
        } else {
            order = [.hotkey, .accessibility]
        }

        var errors: [String] = []
        strategies: for strategy in order {
            switch strategy {
            case .hotkey:
                if needsAccessibility {
                    errors.append(L("Chybí oprávnění Zpřístupnění"))
                    continue
                }
                let log = FocusAttemptLog()
                log.add("hotkey strategy, requested on=\(on)")
                let outcome: HotkeyFocusOutcome = await FocusController.runDetached(
                    timeout: 16,
                    queue: FocusController.axQueue,
                    fallback: HotkeyFocusOutcome.timedOut
                ) {
                    HotkeyFocusDriver.setDoNotDisturb(on, log: log)
                }
                switch outcome {
                case .done(let changed):
                    log.add("result: done (changed=\(changed))")
                    record(.hotkey, on: on, log: log)
                    return succeed(on: on, changed: changed, strategy: .hotkey)
                case .unavailable(let message):
                    log.add("result: unavailable – \(message)")
                    errors.append(message)
                case .failed(let message):
                    log.add("result: failed – \(message)")
                    errors.append(message)
                case .timedOut:
                    // Stisk může pořád probíhat – další strategii nezkoušet (souběh by stav rozházel).
                    log.add("result: timed out")
                    record(.hotkey, on: on, log: log)
                    errors.append(L("Klávesová zkratka Nerušit neodpovídá"))
                    break strategies
                }
                record(.hotkey, on: on, log: log)

            case .accessibility:
                if needsAccessibility {
                    errors.append(L("Chybí oprávnění Zpřístupnění"))
                    continue
                }
                let log = FocusAttemptLog()
                log.add("accessibility strategy, requested on=\(on)")
                let outcome: AXFocusOutcome = await FocusController.runDetached(
                    timeout: 12,
                    queue: FocusController.axQueue,
                    fallback: AXFocusOutcome.timedOut
                ) {
                    ControlCenterFocusDriver.setDoNotDisturb(on, log: log)
                }
                switch outcome {
                case .done(let changed):
                    // Ověření ze souborů Soustředění (pokud jdou číst).
                    if changed {
                        let verified: Bool? = await FocusController.runDetached(timeout: 4, fallback: nil) {
                            FocusController.waitForState(on, seconds: 2.5)
                        }
                        log.add("file verification: \(verified.map { String($0) } ?? "unreadable")")
                        if verified == false {
                            log.add("result: AX reported success, but Focus state did not change")
                            record(.accessibility, on: on, log: log)
                            errors.append(L("Nerušit se po stisku nepřepnulo"))
                            continue
                        }
                    }
                    log.add("result: done (changed=\(changed))")
                    record(.accessibility, on: on, log: log)
                    return succeed(on: on, changed: changed, strategy: .accessibility)
                case .failed(let message):
                    log.add("result: failed – \(message)")
                    record(.accessibility, on: on, log: log)
                    errors.append(message)
                case .timedOut:
                    // UI skript může pořád běžet – výsledek je neznámý, další strategii nezkoušet.
                    log.add("result: timed out")
                    record(.accessibility, on: on, log: log)
                    errors.append(L("Ovládací centrum neodpovídá"))
                    break strategies
                }

            case .privateFramework:
                if privateUnavailable { continue }
                let log = FocusAttemptLog()
                log.add("private framework strategy, requested on=\(on)")
                var before: FocusSnapshot?
                if on {
                    before = await FocusController.runDetached(timeout: 2, fallback: FocusSnapshot?.none) {
                        FocusController.readSnapshotNow()
                    }
                }
                if let before, before.canRead, before.modeID != nil {
                    // Nějaké Soustředění už běží – nic neměnit.
                    log.add("a Focus mode is already active (\(before.modeID ?? "")) – nothing to do")
                    record(.privateFramework, on: on, log: log)
                    return succeed(on: on, changed: false, strategy: .privateFramework)
                }
                let outcome: PrivateDNDOutcome = await FocusController.runDetached(
                    timeout: 4,
                    fallback: PrivateDNDOutcome.failed(L("Služba Nerušit neodpovídá"))
                ) {
                    PrivateDNDClient.shared.set(on)
                }
                switch outcome {
                case .failed(let message):
                    log.add("result: failed – \(message)")
                    record(.privateFramework, on: on, log: log)
                    privateUnavailable = true
                    errors.append(message)
                case .accepted:
                    let verified: Bool? = await FocusController.runDetached(timeout: 4, fallback: nil) {
                        FocusController.waitForState(on, seconds: 2.5)
                    }
                    log.add("request accepted, file verification: \(verified.map { String($0) } ?? "unreadable")")
                    record(.privateFramework, on: on, log: log)
                    if verified == false {
                        privateUnavailable = true
                        errors.append(L("Systém požadavek na Nerušit ignoroval"))
                        continue
                    }
                    return succeed(on: on, changed: true, strategy: .privateFramework)
                }
            }
        }

        let message: String
        if needsAccessibility {
            message = L("Povol NotchMaxu Zpřístupnění, aby mohl přepínat Nerušit")
        } else {
            message = errors.first ?? L("Nerušit se nepodařilo přepnout")
        }
        lastError = message
        return FocusChangeResult(ok: false, changed: false, method: "", error: message)
    }

    private func succeed(on: Bool, changed: Bool, strategy: Strategy) -> FocusChangeResult {
        let name: String
        switch strategy {
        case .hotkey: name = FocusController.methodHotkey
        case .accessibility: name = FocusController.methodAccessibility
        case .privateFramework: name = FocusController.methodPrivate
        }
        method = name
        lastError = nil
        if on {
            if changed { lastOnStrategy = strategy }
        } else {
            lastOnStrategy = nil
        }
        // Rychlejší obnovení HUD / stavu v monitoru.
        FocusModeMonitor.shared.refresh()
        return FocusChangeResult(ok: true, changed: changed, method: name, error: nil)
    }

    private func record(_ strategy: Strategy, on: Bool, log: FocusAttemptLog) {
        let stamp = FocusController.timestamp(Date())
        lastAttemptLogs[strategy.rawValue] = "[\(stamp)] requested on=\(on)\n" + log.text
    }

    // MARK: - Diagnostika

    /// Uloží diagnostický záznam do ~/Library/Logs/NotchMax/focus-diagnostics.txt a vrátí cestu.
    /// Pokud je povolené Zpřístupnění, na chvíli otevře Ovládací centrum a zapíše jeho AX strom.
    func exportDiagnostics() async -> String? {
        refreshPermission()
        let trusted = AXIsProcessTrusted()

        let monitor = FocusModeMonitor.shared
        let monitorLine = "canRead=\(monitor.canRead), activeModeID=\(monitor.activeModeID ?? "nil"), "
            + "activeModeName=\(monitor.activeModeName ?? "nil"), isDoNotDisturbActive=\(monitor.isDoNotDisturbActive)"

        let snapshot: FocusSnapshot? = await FocusController.runDetached(timeout: 3, fallback: FocusSnapshot?.none) {
            FocusController.readSnapshotNow()
        }
        let hotkeyInfo: String = await FocusController.runDetached(timeout: 3, fallback: "(timed out)") {
            HotkeyFocusDriver.diagnosticDescription()
        }
        let fda: String = await FocusController.runDetached(timeout: 3, fallback: "(timed out)") {
            FullDiskAccess.statusDescription
        }
        let tree: String
        if trusted {
            tree = await FocusController.runDetached(timeout: 15, queue: FocusController.axQueue, fallback: "(Control Center did not respond)") {
                ControlCenterFocusDriver.diagnosticTreeDump()
            }
        } else {
            tree = "(Accessibility not granted – tree not available)"
        }

        var out: [String] = []
        out.append("NotchMax – Focus diagnostics")
        out.append("Date: \(FocusController.timestamp(Date()))")
        out.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        let info = Bundle.main.infoDictionary
        let version = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info?["CFBundleVersion"] as? String) ?? "?"
        out.append("NotchMax: \(version) (\(build)), bundle \(Bundle.main.bundleIdentifier ?? "?")")
        out.append("Accessibility trusted: \(trusted)")
        out.append("Full Disk Access: \(fda)")
        out.append("FocusModeMonitor: \(monitorLine)")
        if let snapshot {
            out.append("Direct read of ~/Library/DoNotDisturb/DB: canRead=\(snapshot.canRead), modeID=\(snapshot.modeID ?? "nil"), name=\(snapshot.name ?? "nil")")
        } else {
            out.append("Direct read of ~/Library/DoNotDisturb/DB: (timed out)")
        }
        out.append("Last successful method: \(method.isEmpty ? "-" : method)")
        out.append("Last error: \(lastError ?? "-")")
        out.append("")
        out.append("=== Symbolic hotkey 175 (Turn Do Not Disturb On/Off) ===")
        out.append(hotkeyInfo)
        for strategy in Strategy.allCases {
            out.append("")
            out.append("=== Last attempt: \(strategy.rawValue) ===")
            out.append(lastAttemptLogs[strategy.rawValue] ?? "(no attempt in this session)")
        }
        out.append("")
        out.append("=== Control Center AX tree ===")
        out.append(tree)
        out.append("")
        let text = out.joined(separator: "\n")

        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/NotchMax", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("focus-diagnostics.txt")
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url.path
        } catch {
            NSLog("NotchMax Focus: diagnostics export failed: %@", error.localizedDescription)
            return nil
        }
    }

    nonisolated private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    // MARK: - Pomocné (mimo hlavní vlákno)

    /// Sériová fronta pro UI skriptování a stisk zkratky – i po vypršení timeoutu nepoběží
    /// dvě manipulace současně.
    nonisolated private static let axQueue = DispatchQueue(label: "com.jovan.NotchMax.focus-ax", qos: .userInitiated)

    nonisolated static func readSnapshotNow() -> FocusSnapshot {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB", isDirectory: true)
        return FocusFileWatcher.readSnapshot(directory: dir)
    }

    /// Čeká, až stav Soustředění odpovídá `on`. nil = stav nejde číst (chybí Plný přístup k disku).
    nonisolated static func waitForState(_ on: Bool, seconds: Double) -> Bool? {
        let deadline = Date().addingTimeInterval(seconds)
        while true {
            let snap = readSnapshotNow()
            if !snap.canRead { return nil }
            if (snap.modeID != nil) == on { return true }
            if Date() >= deadline { return false }
            usleep(200_000)
        }
    }

    /// Spustí synchronní práci na pozadí; po `timeout` vrátí `fallback` (práce doběhne sama).
    nonisolated private static func runDetached<T: Sendable>(
        timeout: Double,
        queue: DispatchQueue = .global(qos: .userInitiated),
        fallback: T,
        _ work: @escaping @Sendable () -> T
    ) async -> T {
        await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
            let gate = ResumeGate()
            queue.async {
                let value = work()
                if gate.claim() { continuation.resume(returning: value) }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                if gate.claim() { continuation.resume(returning: fallback) }
            }
        }
    }
}

/// Zajistí, že se continuation obnoví jen jednou.
private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

// MARK: - Strategie 1: systémová klávesová zkratka „Zapnout/vypnout Nerušit“

enum HotkeyFocusOutcome: Sendable {
    case done(changed: Bool)
    /// Strategii nešlo použít (nic se nestisklo) – bezpečné zkusit další.
    case unavailable(String)
    /// Zkratka se stiskla, ale stav se nezměnil.
    case failed(String)
    /// Vypršel časový limit (výsledek neznámý).
    case timedOut
}

/// Symbolická zkratka č. 175 = „Turn Do Not Disturb On/Off“ (Nastavení systému → Klávesnice →
/// Klávesové zkratky → Mission Control), na macOS 12–26 bez výchozí klávesy (vypnutá).
/// Formát v `com.apple.symbolichotkeys` → `AppleSymbolicHotKeys`:
///   "175" = { enabled = 1; value = { parameters = (ascii, keyCode, modifiers); type = standard; }; }
/// `modifiers` jsou masky NX_* (shift 0x20000, control 0x40000, option 0x80000, command 0x100000),
/// stejné hodnoty jako `CGEventFlags`. Vše synchronní – volat mimo hlavní vlákno.
enum HotkeyFocusDriver {
    static let hotKeyID = 175
    private static let domain = "com.apple.symbolichotkeys" as CFString
    private static let prefsKey = "AppleSymbolicHotKeys" as CFString
    static let activateSettingsPath = "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings"

    struct Binding: Sendable, Equatable {
        var ascii: Int
        var keyCode: Int
        var modifiers: Int
        var enabled: Bool

        /// Použitelná pro stisk: zapnutá, s platnou klávesou a aspoň jedním modifikátorem.
        var isUsable: Bool {
            enabled && keyCode >= 0 && keyCode < 0xFFFF && (modifiers & HotkeyFocusDriver.modifierMask) != 0
        }

        var display: String {
            var s = ""
            if modifiers & 0x40000 != 0 { s += "⌃" }
            if modifiers & 0x80000 != 0 { s += "⌥" }
            if modifiers & 0x20000 != 0 { s += "⇧" }
            if modifiers & 0x100000 != 0 { s += "⌘" }
            if modifiers & 0x800000 != 0 { s += "fn " }
            if ascii > 32 && ascii < 127, let scalar = UnicodeScalar(UInt32(ascii)) {
                s += String(Character(scalar)).uppercased()
            } else {
                s += "key \(keyCode)"
            }
            return s + " [\(ascii), \(keyCode), \(modifiers)] enabled=\(enabled)"
        }
    }

    /// shift | control | option | command
    static let modifierMask = 0x20000 | 0x40000 | 0x80000 | 0x100000
    /// ⌃⌥⌘ = 0x1C0000 = 1835008
    private static let ctrlOptCmd = 0x40000 | 0x80000 | 0x100000

    /// Kandidáti, které NotchMax zapíše, když zkratka není nastavená (první volný vyhrává):
    /// ⌃⌥⌘D (keyCode 2), ⌃⌥⌘N (45), ⌃⌥⌘J (38).
    private static let candidates: [Binding] = [
        Binding(ascii: 100, keyCode: 2, modifiers: ctrlOptCmd, enabled: true),
        Binding(ascii: 110, keyCode: 45, modifiers: ctrlOptCmd, enabled: true),
        Binding(ascii: 106, keyCode: 38, modifiers: ctrlOptCmd, enabled: true),
    ]

    static func setDoNotDisturb(_ on: Bool, log: FocusAttemptLog) -> HotkeyFocusOutcome {
        guard AXIsProcessTrusted() else {
            log.add("Accessibility not trusted – cannot post key events")
            return .unavailable(L("Chybí oprávnění Zpřístupnění"))
        }
        // Zkratka je přepínač → bez čitelného stavu by se mohla stisknout „naslepo“ špatně.
        let before = FocusController.readSnapshotNow()
        guard before.canRead else {
            log.add("Focus state (~/Library/DoNotDisturb/DB) is not readable – skipping the toggle shortcut")
            return .unavailable(L("Stav Soustředění nejde přečíst (chybí plný přístup k disku)"))
        }
        log.add("state before: \(before.modeID ?? "off")")
        if (before.modeID != nil) == on {
            return .done(changed: false)
        }

        guard let ensured = ensureBinding(log: log) else {
            return .unavailable(L("Klávesovou zkratku pro Nerušit se nepodařilo nastavit"))
        }
        var binding = ensured.binding
        var activated = false
        if ensured.written {
            activateLive(binding, log: log)
            activated = true
        }

        for attempt in 1...2 {
            if attempt == 2 {
                // Zkratka možná ještě nebyla v systému aktivní – aktivovat a zkusit znovu.
                if !activated {
                    activateLive(binding, log: log)
                    activated = true
                } else {
                    usleep(500_000)
                }
                // Stav se mohl mezitím změnit opožděně → znovu přečíst, nestisknout zbytečně.
                let again = FocusController.readSnapshotNow()
                guard again.canRead else {
                    log.add("state became unreadable – stopping")
                    return .failed(L("Stav Soustředění nejde přečíst (chybí plný přístup k disku)"))
                }
                if (again.modeID != nil) == on {
                    log.add("state changed late to \(again.modeID ?? "off")")
                    return .done(changed: true)
                }
                // Uživatel mohl mezitím zkratku změnit.
                if let fresh = currentBinding(), fresh.isUsable, fresh != binding {
                    log.add("binding changed meanwhile to \(fresh.display)")
                    binding = fresh
                }
            }
            log.add("attempt \(attempt): pressing \(binding.display)")
            guard postCombo(binding) else {
                log.add("could not create CGEvents")
                return .unavailable(L("Klávesovou zkratku nejde odeslat"))
            }
            if let verified = FocusController.waitForState(on, seconds: attempt == 1 ? 2.0 : 2.5) {
                if verified {
                    log.add("verified: Focus is now \(on ? "on" : "off")")
                    return .done(changed: true)
                }
                log.add("attempt \(attempt): state did not change")
            } else {
                log.add("state became unreadable after press")
                return .failed(L("Stav Soustředění nejde přečíst (chybí plný přístup k disku)"))
            }
        }
        return .failed(L("Systém na klávesovou zkratku Nerušit nereagoval"))
    }

    // MARK: Předvolby

    /// Celý slovník `AppleSymbolicHotKeys` (čerstvě z cfprefsd).
    private static func readAll() -> [String: Any]? {
        _ = CFPreferencesAppSynchronize(domain)
        guard let value = CFPreferencesCopyValue(prefsKey, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            return nil
        }
        return value as? [String: Any]
    }

    private static func parseBinding(_ raw: Any?) -> Binding? {
        guard let entry = raw as? [String: Any] else { return nil }
        let enabled = (entry["enabled"] as? NSNumber)?.boolValue ?? false
        guard let value = entry["value"] as? [String: Any],
              let params = value["parameters"] as? [Any], params.count >= 3,
              let ascii = (params[0] as? NSNumber)?.intValue,
              let keyCode = (params[1] as? NSNumber)?.intValue,
              let modifiers = (params[2] as? NSNumber)?.intValue else {
            return Binding(ascii: 65535, keyCode: -1, modifiers: 0, enabled: enabled)
        }
        return Binding(ascii: ascii, keyCode: keyCode, modifiers: modifiers, enabled: enabled)
    }

    static func currentBinding() -> Binding? {
        guard let all = readAll() else { return nil }
        return parseBinding(all[String(hotKeyID)])
    }

    /// Vrátí použitelnou zkratku; když chybí, zapíše první volného kandidáta.
    private static func ensureBinding(log: FocusAttemptLog) -> (binding: Binding, written: Bool)? {
        let all = readAll() ?? [:]
        if let existing = parseBinding(all[String(hotKeyID)]) {
            log.add("existing hotkey 175: \(existing.display)")
            if existing.isUsable { return (existing, false) }
        } else {
            log.add("hotkey 175 has no entry (default = disabled, no key)")
        }

        // Klávesy, které už používají jiné zapnuté symbolické zkratky.
        var taken: [(Int, Int)] = []
        for (key, raw) in all where key != String(hotKeyID) {
            if let b = parseBinding(raw), b.enabled, b.keyCode >= 0 {
                taken.append((b.keyCode, b.modifiers & modifierMask))
            }
        }
        guard let choice = candidates.first(where: { c in
            !taken.contains { $0.0 == c.keyCode && $0.1 == (c.modifiers & modifierMask) }
        }) else {
            log.add("all candidate key combos are taken by other symbolic hotkeys")
            return nil
        }

        let entry: [String: Any] = [
            "enabled": true,
            "value": [
                "parameters": [choice.ascii, choice.keyCode, choice.modifiers],
                "type": "standard",
            ] as [String: Any],
        ]
        let updated = NSMutableDictionary(dictionary: all)
        updated.setObject(entry, forKey: String(hotKeyID) as NSString)
        CFPreferencesSetValue(prefsKey, updated, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let synced = CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        log.add("wrote hotkey 175 = \(choice.display), synchronize=\(synced)")

        if let check = currentBinding(), check.isUsable {
            return (check, true)
        }
        log.add("read-back of hotkey 175 failed – using written value anyway")
        return (choice, true)
    }

    // MARK: Aktivace bez odhlášení

    /// Zkratku udělá aktivní hned: soukromé SkyLight API (`CGSSetSymbolicHotKeyValue` +
    /// `CGSSetSymbolicHotKeyEnabled`, pokud existují) a `activateSettings -u`.
    private static func activateLive(_ binding: Binding, log: FocusAttemptLog) {
        if let setValue = cgsSetValue, let setEnabled = cgsSetEnabled {
            let r1 = setValue(Int64(hotKeyID), UInt64(UInt16(truncatingIfNeeded: binding.ascii)),
                              UInt64(UInt16(truncatingIfNeeded: binding.keyCode)), UInt64(truncatingIfNeeded: binding.modifiers))
            let r2 = setEnabled(Int64(hotKeyID), true)
            log.add("CGSSetSymbolicHotKeyValue=\(r1), CGSSetSymbolicHotKeyEnabled=\(r2)")
        } else {
            log.add("CGS symbolic hotkey API not available")
        }
        runActivateSettings(log: log)
        usleep(400_000)
    }

    private static func runActivateSettings(log: FocusAttemptLog) {
        guard FileManager.default.isExecutableFile(atPath: activateSettingsPath) else {
            log.add("activateSettings not found")
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: activateSettingsPath)
        process.arguments = ["-u"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            log.add("activateSettings failed to start: \(error.localizedDescription)")
            return
        }
        let deadline = Date().addingTimeInterval(4)
        while process.isRunning && Date() < deadline {
            usleep(50_000)
        }
        if process.isRunning {
            process.terminate()
            log.add("activateSettings -u timed out")
        } else {
            log.add("activateSettings -u exit=\(process.terminationStatus)")
        }
    }

    // Soukromé SkyLight funkce (64bitové argumenty jsou bezpečné pro užší C typy v registrech).
    private typealias SetValueFn = @convention(c) (Int64, UInt64, UInt64, UInt64) -> Int32
    private typealias SetEnabledFn = @convention(c) (Int64, Bool) -> Int32

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        if let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
           let sym = dlsym(handle, name) {
            return sym
        }
        // RTLD_DEFAULT = (void *)-2
        return dlsym(UnsafeMutableRawPointer(bitPattern: -2), name)
    }

    private static let cgsSetValue: SetValueFn? = {
        guard let sym = symbol("CGSSetSymbolicHotKeyValue") else { return nil }
        return unsafeBitCast(sym, to: SetValueFn.self)
    }()

    private static let cgsSetEnabled: SetEnabledFn? = {
        guard let sym = symbol("CGSSetSymbolicHotKeyEnabled") else { return nil }
        return unsafeBitCast(sym, to: SetEnabledFn.self)
    }()

    // MARK: Stisk

    /// Pošle kombinaci jako z klávesnice: modifikátory dolů → klávesa → modifikátory nahoru.
    private static func postCombo(_ binding: Binding) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return false }
        let allowed = UInt64(modifierMask | 0x800000)
        let flags = CGEventFlags(rawValue: UInt64(truncatingIfNeeded: binding.modifiers) & allowed)

        var modifierKeys: [(CGKeyCode, CGEventFlags)] = []
        if flags.contains(.maskControl) { modifierKeys.append((59, .maskControl)) }
        if flags.contains(.maskAlternate) { modifierKeys.append((58, .maskAlternate)) }
        if flags.contains(.maskShift) { modifierKeys.append((56, .maskShift)) }
        if flags.contains(.maskCommand) { modifierKeys.append((55, .maskCommand)) }

        let keyCode = CGKeyCode(UInt16(truncatingIfNeeded: binding.keyCode))
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }

        var current: CGEventFlags = []
        for (code, flag) in modifierKeys {
            current.insert(flag)
            if let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true) {
                event.flags = current
                event.post(tap: .cghidEventTap)
            }
            usleep(10_000)
        }

        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        usleep(20_000)
        up.post(tap: .cghidEventTap)
        usleep(10_000)

        for (code, flag) in modifierKeys.reversed() {
            current.remove(flag)
            if let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) {
                event.flags = current
                event.post(tap: .cghidEventTap)
            }
            usleep(10_000)
        }
        return true
    }

    // MARK: Diagnostika

    static func diagnosticDescription() -> String {
        var lines: [String] = []
        if let all = readAll() {
            if let raw = all[String(hotKeyID)] {
                lines.append("raw entry: \(String(describing: raw))")
                if let b = parseBinding(raw) {
                    lines.append("parsed: \(b.display), usable=\(b.isUsable)")
                }
            } else {
                lines.append("no entry for 175 (default: disabled, no key)")
            }
            lines.append("AppleSymbolicHotKeys entries: \(all.count)")
        } else {
            lines.append("com.apple.symbolichotkeys AppleSymbolicHotKeys not readable / missing")
        }
        lines.append("activateSettings present: \(FileManager.default.isExecutableFile(atPath: activateSettingsPath))")
        lines.append("CGSSetSymbolicHotKeyValue available: \(cgsSetValue != nil), CGSSetSymbolicHotKeyEnabled available: \(cgsSetEnabled != nil)")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Strategie 2: Ovládací centrum přes Zpřístupnění

enum AXFocusOutcome: Sendable {
    case done(changed: Bool)
    case failed(String)
    /// Vypršel časový limit (výsledek neznámý).
    case timedOut
}

/// Ovládá přepínač „Nerušit“ v menu baru / Ovládacím centru přes AXUIElement.
/// Vše synchronní – volat mimo hlavní vlákno.
enum ControlCenterFocusDriver {
    private static let controlCenterBundleID = "com.apple.controlcenter"
    private static let focusExtraID = "com.apple.menuextra.focusmode"
    private static let controlCenterExtraID = "com.apple.menuextra.controlcenter"
    private static let dndModeID = "com.apple.donotdisturb.mode.default"

    /// Názvy (bez diakritiky, malými písmeny) přepínače „Nerušit“.
    private static let dndNames: [String] = ["do not disturb", "nerusit", "nicht storen", "ne pas deranger", "no molestar", "non disturbare", "nie przeszkadzac", "nevyrusovat"]
    /// Názvy modulu „Soustředění“ v Ovládacím centru.
    private static let focusNames: [String] = ["focus", "soustredeni", "fokus", "sustredenie", "konzentration", "concentration", "concentracion", "skupienie"]
    /// Názvy položky Ovládací centrum v menu baru (záloha, když chybí identifikátor).
    private static let controlCenterNames: [String] = ["control center", "control centre", "ovladaci centrum", "kontrollzentrum"]

    private static let pressableRoles: Set<String> = ["AXCheckBox", "AXButton", "AXMenuItem", "AXRadioButton", "AXMenuBarItem", "AXToggle", "AXSwitch"]

    static func setDoNotDisturb(_ on: Bool, log: FocusAttemptLog) -> AXFocusOutcome {
        guard AXIsProcessTrusted() else { return .failed(L("Chybí oprávnění Zpřístupnění")) }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: controlCenterBundleID).first else {
            log.add("ControlCenter process not running")
            return .failed(L("Ovládací centrum neběží"))
        }
        let appElement: AXUIElement = AXUIElementCreateApplication(app.processIdentifier)
        _ = AXUIElementSetMessagingTimeout(appElement, 1.0)

        guard let extrasBar = element(appElement, "AXExtrasMenuBar") else {
            log.add("AXExtrasMenuBar not available")
            return .failed(L("Menu bar Ovládacího centra není dostupný"))
        }
        let items: [AXUIElement] = children(extrasBar)
        if items.isEmpty { return .failed(L("Menu bar Ovládacího centra je prázdný")) }
        log.add("menu bar extras: " + items.map { describe($0) }.joined(separator: " ; "))

        var focusItem: AXUIElement? = items.first { identifier($0) == focusExtraID }
        if focusItem == nil {
            // Tahoe: identifikátor se může lišit – hledat „focus“ v identifikátoru.
            focusItem = items.first { item in
                let ident = (identifier(item) ?? "").lowercased()
                return ident.contains("focus") && !ident.contains("controlcenter")
            }
        }
        var controlCenterItem: AXUIElement? = items.first { identifier($0) == controlCenterExtraID }
        if controlCenterItem == nil {
            controlCenterItem = items.first { item in
                let ident = (identifier(item) ?? "").lowercased()
                if ident.contains("controlcenter") && !ident.contains("focus") { return true }
                return texts(of: item).contains { text in controlCenterNames.contains { text.contains($0) } }
            }
        }
        log.add("focus item: \(focusItem.map { describe($0) } ?? "none"), control center item: \(controlCenterItem.map { describe($0) } ?? "none")")

        var lastFailure = L("Přepínač Nerušit nebyl nalezen")
        // 1) Položka Soustředění v menu baru (jen když ji má uživatel zobrazenou).
        if let focusItem {
            switch attempt(menuItem: focusItem, app: appElement, viaControlCenter: false, on: on, log: log) {
            case .done(let changed): return .done(changed: changed)
            case .failed(let message): lastFailure = message
            case .timedOut: lastFailure = L("Ovládací centrum neodpovídá")
            }
        }
        // 2) Ovládací centrum → modul Soustředění.
        if let controlCenterItem {
            switch attempt(menuItem: controlCenterItem, app: appElement, viaControlCenter: true, on: on, log: log) {
            case .done(let changed): return .done(changed: changed)
            case .failed(let message): lastFailure = message
            case .timedOut: lastFailure = L("Ovládací centrum neodpovídá")
            }
        } else if focusItem == nil {
            return .failed(L("V menu baru chybí Ovládací centrum"))
        }
        return .failed(lastFailure)
    }

    // MARK: Průběh

    private static func attempt(menuItem: AXUIElement, app: AXUIElement, viaControlCenter: Bool, on: Bool, log: FocusAttemptLog) -> AXFocusOutcome {
        log.add("opening \(viaControlCenter ? "Control Center" : "Focus menu")")
        let baseline: Int = windowRoots(app).count
        guard press(menuItem) else { return .failed(L("Menu se nepodařilo otevřít")) }

        // Počkat na otevření okna menu.
        let opened = waitUntil(seconds: 1.5) { windowRoots(app).count > baseline }
        log.add("menu window opened: \(opened)")

        var toggle: AXUIElement? = waitFor(seconds: 1.0) { findDNDToggle(app) }

        if toggle == nil && viaControlCenter {
            // V Ovládacím centru je nejdřív potřeba rozbalit modul Soustředění.
            if let module = findFocusModule(app) {
                // Hodnota modulu (pokud ji má) = je aktivní nějaké Soustředění.
                let moduleState: Bool? = state(of: module)
                log.add("focus module: \(describe(module)), state=\(moduleState.map { String($0) } ?? "nil")")
                if moduleState == on {
                    close(menuItem: menuItem, app: app, baseline: baseline)
                    return .done(changed: false)
                }
                // Tahoe: modul může mít vlastní akci „rozbalit“ (AXShowMenu / AXShowAlternateUI).
                let moduleActions = actions(module)
                log.add("focus module actions: \(moduleActions.joined(separator: ","))")
                _ = press(module)
                toggle = waitFor(seconds: 1.5) { findDNDToggle(app) }
                if toggle == nil, moduleState != nil, state(of: module) == on {
                    // Stisk modulu Soustředění přímo přepnul stav (bez rozbalení seznamu).
                    log.add("pressing the module toggled Focus directly")
                    close(menuItem: menuItem, app: app, baseline: baseline)
                    return .done(changed: true)
                }
                if toggle == nil, moduleActions.contains("AXShowMenu") {
                    _ = AXUIElementPerformAction(module, "AXShowMenu" as CFString)
                    toggle = waitFor(seconds: 1.2) { findDNDToggle(app) }
                }
            } else {
                log.add("focus module not found")
            }
        }

        guard let dnd = toggle else {
            log.add("DND toggle not found; tree:\n" + treeDump(app, maxNodes: 300, maxDepth: 12))
            close(menuItem: menuItem, app: app, baseline: baseline)
            return .failed(L("Přepínač Nerušit nebyl nalezen"))
        }

        let current: Bool? = state(of: dnd)
        log.add("DND toggle: \(describe(dnd)), state=\(current.map { String($0) } ?? "nil")")
        if current == on {
            close(menuItem: menuItem, app: app, baseline: baseline)
            return .done(changed: false)
        }

        guard press(dnd) else {
            close(menuItem: menuItem, app: app, baseline: baseline)
            return .failed(L("Přepínač Nerušit nejde stisknout"))
        }

        // Ověření: stav přepínače by se měl změnit (pokud ho jde číst).
        var verified: Bool? = nil
        if current != nil {
            verified = waitUntil(seconds: 1.0) {
                // Prvek mohl být po stisku nahrazen – zkusit i znovu najít.
                if let s = state(of: dnd), s == on { return true }
                if let fresh = findDNDToggle(app), let s = state(of: fresh), s == on { return true }
                return false
            }
        } else {
            usleep(300_000)
        }
        log.add("pressed DND toggle, AX verification: \(verified.map { String($0) } ?? "n/a")")
        close(menuItem: menuItem, app: app, baseline: baseline)

        if verified == false {
            return .failed(L("Nerušit se po stisku nepřepnulo"))
        }
        return .done(changed: true)
    }

    /// Zavře otevřené menu: znovu stiskne položku menu baru, příp. pošle Escape.
    private static func close(menuItem: AXUIElement, app: AXUIElement, baseline: Int) {
        usleep(150_000)
        guard windowRoots(app).count > baseline else { return }
        _ = press(menuItem)
        if waitUntil(seconds: 0.6, { windowRoots(app).count <= baseline }) { return }
        postEscape()
    }

    private static func postEscape() {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 53, keyDown: false)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: Hledání prvků

    /// Kořeny pro hledání: okna procesu ControlCenter (popover menu / Ovládací centrum).
    private static func windowRoots(_ app: AXUIElement) -> [AXUIElement] {
        let windows: [AXUIElement] = elements(app, "AXWindows")
        if !windows.isEmpty { return windows }
        return children(app).filter { el in
            let r = role(el) ?? ""
            return r != "AXMenuBar"
        }
    }

    /// Identifikátor ukazuje na „Nerušit“ (donotdisturb, do-not-disturb, do_not_disturb, samostatné „dnd“).
    private static func isDNDIdentifier(_ ident: String) -> Bool {
        if ident.isEmpty { return false }
        if ident.contains(dndModeID) || ident.contains("donotdisturb") || ident.contains("do-not-disturb")
            || ident.contains("do_not_disturb") || ident.contains("donotdisturbmode") {
            // „focus-modes“ = celý modul, ne přepínač.
            return !ident.contains("focus-modes") || ident.contains("mode.default")
        }
        let tokens = ident.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return tokens.contains { $0 == "dnd" }
    }

    private static func findDNDToggle(_ app: AXUIElement) -> AXUIElement? {
        var byIdentifier: AXUIElement?
        var byTitle: AXUIElement?
        var exact: AXUIElement?
        for root in windowRoots(app) {
            walk(root, maxNodes: 1500, maxDepth: 16) { el in
                let ident: String = (identifier(el) ?? "").lowercased()
                if ident.contains(dndModeID) {
                    exact = el
                    return false
                }
                if byIdentifier == nil, isDNDIdentifier(ident), isPressable(el) {
                    byIdentifier = el
                }
                if byTitle == nil, isPressable(el), !ident.contains("focus-modes") {
                    let names: [String] = texts(of: el)
                    if names.contains(where: { text in dndNames.contains { text.contains($0) } }) {
                        byTitle = el
                    }
                }
                return true
            }
            if exact != nil { break }
        }
        return exact ?? byIdentifier ?? byTitle
    }

    private static func findFocusModule(_ app: AXUIElement) -> AXUIElement? {
        var byIdentifier: AXUIElement?
        var byTitle: AXUIElement?
        for root in windowRoots(app) {
            walk(root, maxNodes: 1500, maxDepth: 16) { el in
                let ident: String = (identifier(el) ?? "").lowercased()
                if ident.contains("focus") && !isDNDIdentifier(ident) && isPressable(el) {
                    byIdentifier = el
                    return false
                }
                if byTitle == nil, isPressable(el) {
                    let names: [String] = texts(of: el)
                    if names.contains(where: { text in focusNames.contains { text == $0 || text.hasPrefix($0) } }) {
                        byTitle = el
                    }
                }
                return true
            }
            if byIdentifier != nil { break }
        }
        return byIdentifier ?? byTitle
    }

    /// Prohledá strom do šířky. `visit` vrací false = zastavit.
    private static func walk(_ root: AXUIElement, maxNodes: Int, maxDepth: Int, _ visit: (AXUIElement) -> Bool) {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var index = 0
        while index < queue.count && index < maxNodes {
            let (el, depth) = queue[index]
            index += 1
            if !visit(el) { return }
            if depth < maxDepth {
                for child in children(el) {
                    queue.append((child, depth + 1))
                }
            }
        }
    }

    private static func isPressable(_ el: AXUIElement) -> Bool {
        if let r = role(el), pressableRoles.contains(r) { return true }
        return actions(el).contains("AXPress")
    }

    /// Normalizované texty prvku (title, description, value, help + texty přímých potomků).
    private static func texts(of el: AXUIElement) -> [String] {
        var raw: [String] = []
        for attr in ["AXTitle", "AXDescription", "AXHelp"] {
            if let s = string(el, attr), !s.isEmpty { raw.append(s) }
        }
        if let s = attribute(el, "AXValue") as? String, !s.isEmpty { raw.append(s) }
        if raw.isEmpty {
            for child in children(el).prefix(4) {
                if let s = string(child, "AXValue"), !s.isEmpty { raw.append(s) }
                if let s = string(child, "AXTitle"), !s.isEmpty { raw.append(s) }
                if let s = string(child, "AXDescription"), !s.isEmpty { raw.append(s) }
            }
        }
        return raw.map { normalize($0) }
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Stav přepínače: AXValue (0/1) u checkboxu, značka u položky menu.
    private static func state(of el: AXUIElement) -> Bool? {
        if let value = attribute(el, "AXValue") {
            if let number = value as? NSNumber { return number.intValue != 0 }
        }
        if role(el) == "AXMenuItem" {
            let mark: String = string(el, "AXMenuItemMarkChar") ?? ""
            return !mark.isEmpty
        }
        return nil
    }

    // MARK: AX primitiva

    private static func attribute(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error: AXError = AXUIElementCopyAttributeValue(el, name as CFString, &value)
        guard error == .success else { return nil }
        return value
    }

    private static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(el, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func elements(_ el: AXUIElement, _ name: String) -> [AXUIElement] {
        guard let value = attribute(el, name), CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
        guard let array = value as? [AnyObject] else { return [] }
        var result: [AXUIElement] = []
        for item in array {
            let ref: CFTypeRef = item
            if CFGetTypeID(ref) == AXUIElementGetTypeID() {
                result.append(ref as! AXUIElement)
            }
        }
        return result
    }

    private static func children(_ el: AXUIElement) -> [AXUIElement] {
        elements(el, "AXChildren")
    }

    private static func string(_ el: AXUIElement, _ name: String) -> String? {
        attribute(el, name) as? String
    }

    private static func identifier(_ el: AXUIElement) -> String? {
        string(el, "AXIdentifier")
    }

    private static func role(_ el: AXUIElement) -> String? {
        string(el, "AXRole")
    }

    private static func actions(_ el: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(el, &names) == .success, let list = names as? [String] else { return [] }
        return list
    }

    @discardableResult
    private static func press(_ el: AXUIElement) -> Bool {
        AXUIElementPerformAction(el, "AXPress" as CFString) == .success
    }

    private static func waitUntil(seconds: Double, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while true {
            if condition() { return true }
            if Date() >= deadline { return false }
            usleep(100_000)
        }
    }

    private static func waitFor<T>(seconds: Double, _ produce: () -> T?) -> T? {
        let deadline = Date().addingTimeInterval(seconds)
        while true {
            if let value = produce() { return value }
            if Date() >= deadline { return nil }
            usleep(120_000)
        }
    }

    // MARK: Diagnostika

    /// Jednořádkový popis prvku: role, subrole, identifikátor, texty, hodnota, akce.
    private static func describe(_ el: AXUIElement) -> String {
        let r: String = role(el) ?? "?"
        let sub: String = string(el, "AXSubrole") ?? ""
        let ident: String = identifier(el) ?? ""
        let names: String = texts(of: el).joined(separator: " | ")
        var valueText = ""
        if let number = attribute(el, "AXValue") as? NSNumber { valueText = " value=\(number)" }
        let acts = actions(el).filter { $0 != "AXScrollToVisible" }
        let actText = acts.isEmpty ? "" : " actions=" + acts.joined(separator: ",")
        return "\(r)\(sub.isEmpty ? "" : "/" + sub) id=\(ident) [\(names)]\(valueText)\(actText)"
    }

    /// Strom oken procesu ControlCenter (odsazený podle hloubky).
    private static func treeDump(_ app: AXUIElement, maxNodes: Int, maxDepth: Int) -> String {
        var lines: [String] = []
        var count = 0
        func visit(_ el: AXUIElement, depth: Int) {
            guard count < maxNodes else { return }
            count += 1
            lines.append(String(repeating: "  ", count: depth) + describe(el))
            guard depth < maxDepth else { return }
            for child in children(el) {
                visit(child, depth: depth + 1)
            }
        }
        for root in windowRoots(app) {
            visit(root, depth: 0)
        }
        if count >= maxNodes { lines.append("… (truncated at \(maxNodes) nodes)") }
        return lines.isEmpty ? "(no windows)" : lines.joined(separator: "\n")
    }

    /// Pro diagnostiku: položky menu baru, pak otevře Ovládací centrum, zapíše strom
    /// (+ kandidáty na modul Soustředění a přepínač Nerušit) a zase ho zavře. Nic nepřepíná.
    static func diagnosticTreeDump() -> String {
        guard AXIsProcessTrusted() else { return "(Accessibility not granted)" }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: controlCenterBundleID).first else {
            return "(ControlCenter process not running)"
        }
        let appElement: AXUIElement = AXUIElementCreateApplication(app.processIdentifier)
        _ = AXUIElementSetMessagingTimeout(appElement, 1.0)

        var out: [String] = []
        guard let extrasBar = element(appElement, "AXExtrasMenuBar") else {
            return "(AXExtrasMenuBar not available)"
        }
        let items = children(extrasBar)
        out.append("Menu bar extras (\(items.count)):")
        for item in items { out.append("  " + describe(item)) }

        var controlCenterItem: AXUIElement? = items.first { identifier($0) == controlCenterExtraID }
        if controlCenterItem == nil {
            controlCenterItem = items.first { item in
                let ident = (identifier(item) ?? "").lowercased()
                if ident.contains("controlcenter") && !ident.contains("focus") { return true }
                return texts(of: item).contains { text in controlCenterNames.contains { text.contains($0) } }
            }
        }
        guard let ccItem = controlCenterItem else {
            out.append("(Control Center menu bar item not found)")
            return out.joined(separator: "\n")
        }

        let baseline = windowRoots(appElement).count
        guard press(ccItem) else {
            out.append("(Control Center could not be opened)")
            return out.joined(separator: "\n")
        }
        _ = waitUntil(seconds: 1.5) { windowRoots(appElement).count > baseline }
        usleep(300_000)
        out.append("")
        out.append("Control Center window:")
        out.append(treeDump(appElement, maxNodes: 400, maxDepth: 10))

        if let module = findFocusModule(appElement) {
            out.append("")
            out.append("Focus module candidate: " + describe(module))
            out.append("DND toggle candidate (before expanding): " + (findDNDToggle(appElement).map { describe($0) } ?? "none"))
        } else {
            out.append("")
            out.append("Focus module candidate: none")
        }
        close(menuItem: ccItem, app: appElement, baseline: baseline)
        return out.joined(separator: "\n")
    }
}

// MARK: - Strategie 3: soukromý DoNotDisturb.framework

enum PrivateDNDOutcome: Sendable {
    case accepted
    case failed(String)
}

/// Volá `DNDModeAssertionService` přes Objective-C runtime. Bez Apple entitlementu
/// (`com.apple.private.donotdisturb…`) daemon požadavek nejspíš odmítne – volající
/// proto výsledek ověřuje.
final class PrivateDNDClient: @unchecked Sendable {
    static let shared = PrivateDNDClient()

    private let lock = NSLock()
    private var service: AnyObject?
    private var loaded = false

    private typealias ServiceFn = @convention(c) (AnyObject, Selector, NSString) -> Unmanaged<AnyObject>?
    private typealias DetailsFn = @convention(c) (AnyObject, Selector, NSString, NSString, AnyObject?) -> Unmanaged<AnyObject>?
    private typealias TakeFn = @convention(c) (AnyObject, Selector, AnyObject, AutoreleasingUnsafeMutablePointer<NSError?>?) -> UnsafeRawPointer?
    private typealias InvalidateFn = @convention(c) (AnyObject, Selector, AutoreleasingUnsafeMutablePointer<NSError?>?) -> UnsafeRawPointer?

    private init() {}

    func set(_ on: Bool) -> PrivateDNDOutcome {
        lock.lock()
        defer { lock.unlock() }

        guard let service = obtainService() else {
            return .failed(L("DoNotDisturb.framework není dostupný"))
        }

        if on {
            guard let detailsClass: AnyClass = NSClassFromString("DNDModeAssertionDetails") else {
                return .failed(L("Nepodporovaná verze DoNotDisturb.framework"))
            }
            let detailsSel = NSSelectorFromString("userRequestedAssertionDetailsWithIdentifier:modeIdentifier:lifetime:")
            guard let detailsMethod = class_getClassMethod(detailsClass, detailsSel) else {
                return .failed(L("Nepodporovaná verze DoNotDisturb.framework"))
            }
            let makeDetails = unsafeBitCast(method_getImplementation(detailsMethod), to: DetailsFn.self)
            guard let details = makeDetails(detailsClass as AnyObject, detailsSel,
                                            "com.apple.donotdisturb.control-center.manual" as NSString,
                                            "com.apple.donotdisturb.mode.default" as NSString,
                                            nil)?.takeUnretainedValue() else {
                return .failed(L("Nepodařilo se vytvořit požadavek na Nerušit"))
            }

            let takeSel = NSSelectorFromString("takeModeAssertionWithDetails:error:")
            guard let serviceClass: AnyClass = object_getClass(service),
                  let takeMethod = class_getInstanceMethod(serviceClass, takeSel) else {
                return .failed(L("Nepodporovaná verze DoNotDisturb.framework"))
            }
            let take = unsafeBitCast(method_getImplementation(takeMethod), to: TakeFn.self)
            var error: NSError?
            let assertion = take(service, takeSel, details, &error)
            if let error {
                return .failed(L("Systém odmítl Nerušit (%ld)", error.code))
            }
            if assertion == nil {
                return .failed(L("Systém odmítl Nerušit"))
            }
            return .accepted
        } else {
            let invalidateSel = NSSelectorFromString("invalidateAllActiveModeAssertionsWithError:")
            guard let serviceClass: AnyClass = object_getClass(service),
                  let invalidateMethod = class_getInstanceMethod(serviceClass, invalidateSel) else {
                return .failed(L("Nepodporovaná verze DoNotDisturb.framework"))
            }
            let invalidate = unsafeBitCast(method_getImplementation(invalidateMethod), to: InvalidateFn.self)
            var error: NSError?
            _ = invalidate(service, invalidateSel, &error)
            if let error {
                return .failed(L("Systém odmítl vypnutí Nerušit (%ld)", error.code))
            }
            return .accepted
        }
    }

    /// Načte framework a vytvoří službu (volat pod zámkem).
    private func obtainService() -> AnyObject? {
        if let service { return service }
        if !loaded {
            loaded = true
            _ = dlopen("/System/Library/PrivateFrameworks/DoNotDisturb.framework/DoNotDisturb", RTLD_NOW)
        }
        guard let serviceClass: AnyClass = NSClassFromString("DNDModeAssertionService") else { return nil }
        let sel = NSSelectorFromString("serviceForClientIdentifier:")
        guard let method = class_getClassMethod(serviceClass, sel) else { return nil }
        let make = unsafeBitCast(method_getImplementation(method), to: ServiceFn.self)
        let clientID: String = Bundle.main.bundleIdentifier ?? "com.jovan.NotchMax"
        guard let created = make(serviceClass as AnyObject, sel, clientID as NSString)?.takeUnretainedValue() else {
            return nil
        }
        service = created
        return created
    }
}
