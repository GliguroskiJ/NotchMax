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
    /// Strategie, která uspěla (prázdné při neúspěchu).
    let method: String
    let error: String?
}

/// Zapíná/vypíná macOS „Nerušit“ (Soustředění) bez Apple Zkratek.
///
/// Veřejné API pro nastavení Focusu neexistuje. Strategie v pořadí:
///  1. Zpřístupnění (AXUIElement) – otevře v menu baru položku Soustředění, příp.
///     Ovládací centrum → modul Soustředění, stiskne přepínač „Nerušit“ a menu zavře.
///     Stav přepínače se čte z AXValue, takže výsledek je ověřený.
///  2. Soukromý DoNotDisturb.framework (`DNDModeAssertionService`) – daemon ho
///     u aplikací bez interního Apple entitlementu obvykle odmítne; zkouší se jen jako
///     záloha, výsledek se ověřuje z ~/Library/DoNotDisturb/DB (pokud je čitelné).
@MainActor
final class FocusController: ObservableObject {
    static let shared = FocusController()

    @Published var lastError: String?
    /// Strategie, která naposledy uspěla.
    @Published private(set) var method: String = ""
    /// Chybí oprávnění Zpřístupnění (hlavní strategie bez něj nefunguje).
    @Published private(set) var needsAccessibility: Bool = !AXIsProcessTrusted()
    @Published private(set) var isBusy = false

    private enum Strategy {
        case accessibility
        case privateFramework
    }

    static let methodAccessibility = "Ovládací centrum (Zpřístupnění)"
    static let methodPrivate = "DoNotDisturb.framework"

    /// Řetěz požadavků – volání se provádějí postupně, nikdy souběžně.
    private var chain: Task<FocusChangeResult, Never>?
    /// Strategie, kterou se „Nerušit“ naposledy zapnulo (pro vypnutí se zkusí první).
    private var lastOnStrategy: Strategy?
    /// Soukromé API už jednou selhalo – v této relaci se nezkouší znovu.
    private var privateUnavailable = false

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
            order = [.accessibility, .privateFramework]
        } else if lastOnStrategy == .privateFramework {
            order = [.privateFramework, .accessibility]
        } else {
            order = [.accessibility]
        }

        var errors: [String] = []
        strategies: for strategy in order {
            switch strategy {
            case .accessibility:
                if needsAccessibility {
                    errors.append("Chybí oprávnění Zpřístupnění")
                    continue
                }
                let outcome: AXFocusOutcome = await FocusController.runDetached(
                    timeout: 10,
                    queue: FocusController.axQueue,
                    fallback: AXFocusOutcome.timedOut
                ) {
                    ControlCenterFocusDriver.setDoNotDisturb(on)
                }
                switch outcome {
                case .done(let changed):
                    return succeed(on: on, changed: changed, strategy: .accessibility)
                case .failed(let message):
                    NSLog("NotchMax Focus (AX): %@", message)
                    errors.append(message)
                case .timedOut:
                    // UI skript může pořád běžet – výsledek je neznámý, další strategii
                    // nezkoušet (souběh by stav rozházel).
                    NSLog("NotchMax Focus (AX): Ovládací centrum neodpovídá")
                    errors.append("Ovládací centrum neodpovídá")
                    break strategies
                }

            case .privateFramework:
                if privateUnavailable { continue }
                var before: FocusSnapshot?
                if on {
                    before = await FocusController.runDetached(timeout: 2, fallback: FocusSnapshot?.none) {
                        FocusController.readSnapshotNow()
                    }
                }
                if let before, before.canRead, before.modeID != nil {
                    // Nějaké Soustředění už běží – nic neměnit.
                    return succeed(on: on, changed: false, strategy: .privateFramework)
                }
                let outcome: PrivateDNDOutcome = await FocusController.runDetached(
                    timeout: 4,
                    fallback: PrivateDNDOutcome.failed("Služba Nerušit neodpovídá")
                ) {
                    PrivateDNDClient.shared.set(on)
                }
                switch outcome {
                case .failed(let message):
                    NSLog("NotchMax Focus (DND framework): %@", message)
                    privateUnavailable = true
                    errors.append(message)
                case .accepted:
                    let verified: Bool? = await FocusController.runDetached(timeout: 4, fallback: nil) {
                        FocusController.waitForState(on, seconds: 2.5)
                    }
                    if verified == false {
                        NSLog("NotchMax Focus (DND framework): požadavek přijat, ale stav se nezměnil")
                        privateUnavailable = true
                        errors.append("Systém požadavek na Nerušit ignoroval")
                        continue
                    }
                    return succeed(on: on, changed: true, strategy: .privateFramework)
                }
            }
        }

        let message: String
        if needsAccessibility {
            message = "Povol NotchMaxu Zpřístupnění, aby mohl přepínat Nerušit"
        } else {
            message = errors.first ?? "Nerušit se nepodařilo přepnout"
        }
        lastError = message
        return FocusChangeResult(ok: false, changed: false, method: "", error: message)
    }

    private func succeed(on: Bool, changed: Bool, strategy: Strategy) -> FocusChangeResult {
        let name: String = strategy == .accessibility ? FocusController.methodAccessibility : FocusController.methodPrivate
        method = name
        lastError = nil
        if on {
            if changed { lastOnStrategy = strategy }
        } else {
            lastOnStrategy = nil
        }
        return FocusChangeResult(ok: true, changed: changed, method: name, error: nil)
    }

    // MARK: - Pomocné (mimo hlavní vlákno)

    /// Sériová fronta pro UI skriptování – i po vypršení timeoutu nepoběží dvě
    /// manipulace s Ovládacím centrem současně.
    nonisolated private static let axQueue = DispatchQueue(label: "com.jovan.NotchMax.focus-ax", qos: .userInitiated)

    nonisolated private static func readSnapshotNow() -> FocusSnapshot {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB", isDirectory: true)
        return FocusFileWatcher.readSnapshot(directory: dir)
    }

    /// Čeká, až stav Soustředění odpovídá `on`. nil = stav nejde číst (chybí Plný přístup k disku).
    nonisolated private static func waitForState(_ on: Bool, seconds: Double) -> Bool? {
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

// MARK: - Strategie 1: Ovládací centrum přes Zpřístupnění

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
    private static let dndNames: [String] = ["do not disturb", "nerusit", "nicht storen", "ne pas deranger", "no molestar", "non disturbare"]
    /// Názvy modulu „Soustředění“ v Ovládacím centru.
    private static let focusNames: [String] = ["focus", "soustredeni", "fokus", "sustredenie", "konzentration", "concentration"]
    /// Názvy položky Ovládací centrum v menu baru (záloha, když chybí identifikátor).
    private static let controlCenterNames: [String] = ["control center", "control centre", "ovladaci centrum"]

    private static let pressableRoles: Set<String> = ["AXCheckBox", "AXButton", "AXMenuItem", "AXRadioButton", "AXMenuBarItem", "AXToggle"]

    static func setDoNotDisturb(_ on: Bool) -> AXFocusOutcome {
        guard AXIsProcessTrusted() else { return .failed("Chybí oprávnění Zpřístupnění") }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: controlCenterBundleID).first else {
            return .failed("Ovládací centrum neběží")
        }
        let appElement: AXUIElement = AXUIElementCreateApplication(app.processIdentifier)
        _ = AXUIElementSetMessagingTimeout(appElement, 1.0)

        guard let extrasBar = element(appElement, "AXExtrasMenuBar") else {
            return .failed("Menu bar Ovládacího centra není dostupný")
        }
        let items: [AXUIElement] = children(extrasBar)
        if items.isEmpty { return .failed("Menu bar Ovládacího centra je prázdný") }

        let focusItem: AXUIElement? = items.first { identifier($0) == focusExtraID }
        var controlCenterItem: AXUIElement? = items.first { identifier($0) == controlCenterExtraID }
        if controlCenterItem == nil {
            controlCenterItem = items.first { item in
                texts(of: item).contains { text in controlCenterNames.contains { text.contains($0) } }
            }
        }

        var lastFailure = "Přepínač Nerušit nebyl nalezen"
        // 1) Položka Soustředění v menu baru (jen když ji má uživatel zobrazenou).
        if let focusItem {
            switch attempt(menuItem: focusItem, app: appElement, viaControlCenter: false, on: on) {
            case .done(let changed): return .done(changed: changed)
            case .failed(let message): lastFailure = message
            case .timedOut: lastFailure = "Ovládací centrum neodpovídá"
            }
        }
        // 2) Ovládací centrum → modul Soustředění.
        if let controlCenterItem {
            switch attempt(menuItem: controlCenterItem, app: appElement, viaControlCenter: true, on: on) {
            case .done(let changed): return .done(changed: changed)
            case .failed(let message): lastFailure = message
            case .timedOut: lastFailure = "Ovládací centrum neodpovídá"
            }
        } else if focusItem == nil {
            return .failed("V menu baru chybí Ovládací centrum")
        }
        return .failed(lastFailure)
    }

    // MARK: Průběh

    private static func attempt(menuItem: AXUIElement, app: AXUIElement, viaControlCenter: Bool, on: Bool) -> AXFocusOutcome {
        let baseline: Int = windowRoots(app).count
        guard press(menuItem) else { return .failed("Menu se nepodařilo otevřít") }

        // Počkat na otevření okna menu.
        _ = waitUntil(seconds: 1.5) { windowRoots(app).count > baseline }

        var toggle: AXUIElement? = waitFor(seconds: 1.0) { findDNDToggle(app) }

        if toggle == nil && viaControlCenter {
            // V Ovládacím centru je nejdřív potřeba rozbalit modul Soustředění.
            if let module = findFocusModule(app) {
                // Hodnota modulu (pokud ji má) = je aktivní nějaké Soustředění.
                let moduleState: Bool? = state(of: module)
                if moduleState == on {
                    close(menuItem: menuItem, app: app, baseline: baseline)
                    return .done(changed: false)
                }
                _ = press(module)
                toggle = waitFor(seconds: 1.5) { findDNDToggle(app) }
                if toggle == nil, moduleState != nil, state(of: module) == on {
                    // Stisk modulu Soustředění přímo přepnul stav (bez rozbalení seznamu).
                    close(menuItem: menuItem, app: app, baseline: baseline)
                    return .done(changed: true)
                }
            }
        }

        guard let dnd = toggle else {
            logTree(app)
            close(menuItem: menuItem, app: app, baseline: baseline)
            return .failed("Přepínač Nerušit nebyl nalezen")
        }

        let current: Bool? = state(of: dnd)
        if current == on {
            close(menuItem: menuItem, app: app, baseline: baseline)
            return .done(changed: false)
        }

        guard press(dnd) else {
            close(menuItem: menuItem, app: app, baseline: baseline)
            return .failed("Přepínač Nerušit nejde stisknout")
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
        close(menuItem: menuItem, app: app, baseline: baseline)

        if verified == false {
            return .failed("Nerušit se po stisku nepřepnulo")
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

    private static func findDNDToggle(_ app: AXUIElement) -> AXUIElement? {
        var byTitle: AXUIElement?
        var found: AXUIElement?
        for root in windowRoots(app) {
            walk(root, maxNodes: 1500, maxDepth: 14) { el in
                let ident: String = (identifier(el) ?? "").lowercased()
                if ident.contains(dndModeID) {
                    found = el
                    return false
                }
                if byTitle == nil, isPressable(el), !ident.contains("focus-modes") {
                    let names: [String] = texts(of: el)
                    if names.contains(where: { text in dndNames.contains { text.contains($0) } }) {
                        byTitle = el
                    }
                }
                return true
            }
            if found != nil { break }
        }
        return found ?? byTitle
    }

    private static func findFocusModule(_ app: AXUIElement) -> AXUIElement? {
        var byIdentifier: AXUIElement?
        var byTitle: AXUIElement?
        for root in windowRoots(app) {
            walk(root, maxNodes: 1500, maxDepth: 14) { el in
                let ident: String = (identifier(el) ?? "").lowercased()
                if ident.contains("focus") && !ident.contains("donotdisturb") && isPressable(el) {
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

    /// Diagnostika do Console.app, když se přepínač nenajde.
    private static func logTree(_ app: AXUIElement) {
        var lines: [String] = []
        for root in windowRoots(app) {
            walk(root, maxNodes: 200, maxDepth: 10) { el in
                let r: String = role(el) ?? "?"
                let ident: String = identifier(el) ?? ""
                let names: String = texts(of: el).joined(separator: " | ")
                lines.append("\(r) id=\(ident) \(names)")
                return true
            }
        }
        NSLog("NotchMax Focus (AX) strom Ovládacího centra:\n%@", lines.joined(separator: "\n"))
    }
}

// MARK: - Strategie 2: soukromý DoNotDisturb.framework

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
            return .failed("DoNotDisturb.framework není dostupný")
        }

        if on {
            guard let detailsClass: AnyClass = NSClassFromString("DNDModeAssertionDetails") else {
                return .failed("Chybí DNDModeAssertionDetails")
            }
            let detailsSel = NSSelectorFromString("userRequestedAssertionDetailsWithIdentifier:modeIdentifier:lifetime:")
            guard let detailsMethod = class_getClassMethod(detailsClass, detailsSel) else {
                return .failed("Nepodporovaná verze DoNotDisturb.framework")
            }
            let makeDetails = unsafeBitCast(method_getImplementation(detailsMethod), to: DetailsFn.self)
            guard let details = makeDetails(detailsClass as AnyObject, detailsSel,
                                            "com.apple.donotdisturb.control-center.manual" as NSString,
                                            "com.apple.donotdisturb.mode.default" as NSString,
                                            nil)?.takeUnretainedValue() else {
                return .failed("Nepodařilo se vytvořit požadavek na Nerušit")
            }

            let takeSel = NSSelectorFromString("takeModeAssertionWithDetails:error:")
            guard let serviceClass: AnyClass = object_getClass(service),
                  let takeMethod = class_getInstanceMethod(serviceClass, takeSel) else {
                return .failed("Nepodporovaná verze DoNotDisturb.framework")
            }
            let take = unsafeBitCast(method_getImplementation(takeMethod), to: TakeFn.self)
            var error: NSError?
            let assertion = take(service, takeSel, details, &error)
            if let error {
                return .failed("Systém odmítl Nerušit (\(error.code))")
            }
            if assertion == nil {
                return .failed("Systém odmítl Nerušit")
            }
            return .accepted
        } else {
            let invalidateSel = NSSelectorFromString("invalidateAllActiveModeAssertionsWithError:")
            guard let serviceClass: AnyClass = object_getClass(service),
                  let invalidateMethod = class_getInstanceMethod(serviceClass, invalidateSel) else {
                return .failed("Nepodporovaná verze DoNotDisturb.framework")
            }
            let invalidate = unsafeBitCast(method_getImplementation(invalidateMethod), to: InvalidateFn.self)
            var error: NSError?
            _ = invalidate(service, invalidateSel, &error)
            if let error {
                return .failed("Systém odmítl vypnutí Nerušit (\(error.code))")
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
