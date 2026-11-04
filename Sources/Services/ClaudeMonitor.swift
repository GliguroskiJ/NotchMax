import Foundation
import AppKit
import Darwin

// MARK: - Model

/// Stav jedné relace Claude Code.
enum ClaudeSessionState: String, Sendable, Equatable {
    /// Claude právě pracuje (generuje, volá nástroje).
    case working
    /// Claude čeká na uživatele (povolení nástroje, dotaz).
    case waiting
    /// Tah je dokončený / relace jen leží.
    case idle

    var title: String {
        switch self {
        case .working: return L("Pracuje")
        case .waiting: return L("Čeká na tebe")
        case .idle: return L("Nečinný")
        }
    }
}

struct ClaudeSession: Identifiable, Equatable, Sendable {
    /// UUID relace (= název souboru transkriptu bez přípony).
    let id: String
    var projectName: String
    var cwd: String
    var branch: String?
    /// Název relace vygenerovaný Claude Code (pokud existuje).
    var title: String?
    /// Prvních ~80 znaků poslední zprávy uživatele.
    var lastPrompt: String?
    /// Krátký úryvek poslední textové odpovědi asistenta.
    var lastReply: String?
    /// Text upozornění z hooku Notification (např. žádost o povolení).
    var attentionMessage: String?
    var state: ClaudeSessionState
    var lastActivity: Date
    /// Proces Claude Code s touto relací ještě běží (podle ~/.claude/sessions).
    var isRunning: Bool
}

/// Událost pro krátké bliknutí notche.
struct ClaudeEvent: Equatable, Sendable {
    enum Kind: Sendable, Equatable {
        /// Relace dokončila tah (pracuje → nečinný).
        case finished
        /// Relace potřebuje pozornost (povolení, dotaz).
        case needsAttention
    }

    let sessionName: String
    let kind: Kind
    let date: Date
}

enum ClaudeHooksError: LocalizedError {
    case invalidSettings
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidSettings:
            return L("Soubor ~/.claude/settings.json není platný JSON objekt. Oprav ho ručně, NotchMax ho nepřepíše.")
        case .writeFailed(let reason):
            return L("Nepodařilo se upravit ~/.claude/settings.json: %@", reason)
        }
    }
}

// MARK: - Monitor

/// Přehled relací Claude Code (CLI) běžících na tomto Macu.
///
/// Zdroje dat (vše jen lokálně, nic se neposílá):
/// 1. Transkripty `~/.claude/projects/<cesta>/<uuid>.jsonl` – čte se jen konec souboru.
/// 2. Registr běžících procesů `~/.claude/sessions/<pid>.json` (novější verze Claude Code).
/// 3. Volitelné hooky Claude Code, které zapisují události do
///    `~/Library/Application Support/NotchMax/claude-events.jsonl` – nejpřesnější stav.
@MainActor
final class ClaudeMonitor: ObservableObject {
    static let shared = ClaudeMonitor()

    @Published private(set) var sessions: [ClaudeSession] = []
    @Published private(set) var hooksInstalled: Bool = false
    /// Poslední přechod stavu (dokončený tah / potřeba pozornosti) – pro bliknutí notche.
    @Published private(set) var lastEvent: ClaudeEvent?

    var isWorking: Bool { sessions.contains { $0.state == .working } }
    var waitingCount: Int { sessions.filter { $0.state == .waiting }.count }
    var workingCount: Int { sessions.filter { $0.state == .working }.count }
    /// Pracující + čekající relace.
    var activeCount: Int { sessions.filter { $0.state != .idle }.count }

    private let scanner = ClaudeScanner()
    private var previousStates: [String: ClaudeSessionState] = [:]
    private var hasInitialScan = false

    private init() {
        hooksInstalled = ClaudeHooksInstaller.isInstalled()
        let handler: @Sendable (ClaudeScanResult) -> Void = { [weak self] result in
            Task { @MainActor in
                self?.apply(result)
            }
        }
        scanner.start(onResult: handler)
    }

    /// Okamžitě znovu načte vše (včetně úplného průchodu složkou projektů).
    func refresh() {
        scanner.requestScan(full: true)
    }

    func installHooks() throws {
        try ClaudeHooksInstaller.install()
        hooksInstalled = ClaudeHooksInstaller.isInstalled()
        refresh()
    }

    func uninstallHooks() throws {
        try ClaudeHooksInstaller.uninstall()
        hooksInstalled = ClaudeHooksInstaller.isInstalled()
        refresh()
    }

    /// Otevře pracovní složku relace v Terminálu.
    func open(_ session: ClaudeSession) {
        guard !session.cwd.isEmpty,
              FileManager.default.fileExists(atPath: session.cwd) else { return }
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([URL(fileURLWithPath: session.cwd, isDirectory: true)],
                                withApplicationAt: terminal,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    /// Zobrazí pracovní složku relace ve Finderu.
    func revealInFinder(_ session: ClaudeSession) {
        guard !session.cwd.isEmpty else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: session.cwd)
    }

    /// Zkopíruje příkaz pro obnovení relace (`cd … && claude --resume <id>`).
    func copyResumeCommand(_ session: ClaudeSession) {
        let escapedPath = session.cwd.replacingOccurrences(of: "'", with: "'\\''")
        let command = session.cwd.isEmpty
            ? "claude --resume \(session.id)"
            : "cd '\(escapedPath)' && claude --resume \(session.id)"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
    }

    private func apply(_ result: ClaudeScanResult) {
        if hooksInstalled != result.hooksInstalled {
            hooksInstalled = result.hooksInstalled
        }

        // Přechody stavů → událost pro notch (ne při prvním načtení).
        if hasInitialScan {
            var event: ClaudeEvent?
            for session in result.sessions {
                let previous = previousStates[session.id]
                if session.state == .waiting && previous != nil && previous != .waiting {
                    event = ClaudeEvent(sessionName: session.projectName, kind: .needsAttention, date: Date())
                    break
                }
                if previous == .working && session.state == .idle && event == nil {
                    event = ClaudeEvent(sessionName: session.projectName, kind: .finished, date: Date())
                }
            }
            if let event { lastEvent = event }
        }
        hasInitialScan = true

        var states: [String: ClaudeSessionState] = [:]
        for session in result.sessions { states[session.id] = session.state }
        previousStates = states

        if sessions != result.sessions {
            sessions = result.sessions
        }
    }
}

// MARK: - Výsledek skenu

struct ClaudeScanResult: Sendable {
    let sessions: [ClaudeSession]
    let hooksInstalled: Bool
}

// MARK: - Skener (běží výhradně na vlastní sériové frontě)

private struct FileStamp: Equatable {
    let mtime: Date
    let size: UInt64
}

private enum TranscriptLastKind {
    case unknown
    case userPrompt
    case toolResult
    case assistantTool
    case assistantText
    case interrupted
    case command
}

private struct TranscriptInfo {
    var stamp: FileStamp
    var cwd: String?
    var branch: String?
    var title: String?
    var lastPrompt: String?
    var lastReply: String?
    var lastKind: TranscriptLastKind = .unknown
}

private struct HookState {
    var event: String
    var ts: Date
    var cwd: String?
    var transcriptPath: String?
    var notificationType: String?
    var message: String?
    var prompt: String?
}

private struct RegistryEntry {
    let sessionId: String
    let cwd: String?
    let status: String?
    let statusUpdated: Date?
    let alive: Bool
}

/// Veškerá práce se soubory. Stav se mění jen na `queue`, proto @unchecked Sendable.
private final class ClaudeScanner: @unchecked Sendable {
    // Konstanty
    private let pollInterval: TimeInterval = 2
    private let fullScanInterval: TimeInterval = 10
    private let workingWindow: TimeInterval = 15
    private let recentWindow: TimeInterval = 24 * 3600
    private let maxSessions = 8
    private let transcriptTailBytes: UInt64 = 64 * 1024
    private let eventsTailBytes: UInt64 = 256 * 1024
    private let eventsMaxBytes: UInt64 = 4 * 1024 * 1024

    private let queue = DispatchQueue(label: "cz.notchmax.claude-monitor", qos: .utility)
    private let fm = FileManager()
    private var timer: DispatchSourceTimer?
    private var onResult: (@Sendable (ClaudeScanResult) -> Void)?

    private let projectsDir: URL
    private let registryDir: URL
    private let eventsURL: URL
    private let settingsURL: URL

    // Stav (jen na `queue`)
    private var candidates: [String: FileStamp] = [:]          // cesta transkriptu → razítko
    private var transcripts: [String: TranscriptInfo] = [:]    // cesta transkriptu → data
    private var lastFullScan: Date = .distantPast
    private var eventsStamp: FileStamp?
    private var hookStates: [String: HookState] = [:]          // session_id → poslední událost
    private var settingsStamp: FileStamp?
    private var hooksInstalled = false

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let claudeDir = home.appendingPathComponent(".claude", isDirectory: true)
        projectsDir = claudeDir.appendingPathComponent("projects", isDirectory: true)
        registryDir = claudeDir.appendingPathComponent("sessions", isDirectory: true)
        settingsURL = claudeDir.appendingPathComponent("settings.json")
        eventsURL = ClaudeHooksInstaller.eventsURL
    }

    func start(onResult: @escaping @Sendable (ClaudeScanResult) -> Void) {
        queue.async {
            self.onResult = onResult
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: self.pollInterval, leeway: .milliseconds(300))
            timer.setEventHandler { [weak self] in
                self?.tick(full: false)
            }
            self.timer = timer
            timer.resume()
        }
    }

    func requestScan(full: Bool) {
        queue.async { [weak self] in
            self?.tick(full: full)
        }
    }

    // MARK: Hlavní smyčka

    private func tick(full: Bool) {
        let now = Date()
        if full || now.timeIntervalSince(lastFullScan) >= fullScanInterval {
            fullScan(now: now)
        } else {
            quickScan()
        }
        refreshHookEvents()
        refreshSettings()
        let registry = readRegistry()
        addExtraCandidates(registry: registry)
        refreshTranscripts()
        let sessions = buildSessions(now: now, registry: registry)
        onResult?(ClaudeScanResult(sessions: sessions, hooksInstalled: hooksInstalled))
    }

    // MARK: Soubory transkriptů

    private func stamp(atPath path: String) -> FileStamp? {
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let mtime = attrs[.modificationDate] as? Date else { return nil }
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        return FileStamp(mtime: mtime, size: size)
    }

    /// Projde všechny složky projektů a vybere transkripty změněné za posledních 24 h.
    private func fullScan(now: Date) {
        lastFullScan = now
        var found: [String: FileStamp] = [:]
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]
        let projectDirs = (try? fm.contentsOfDirectory(at: projectsDir,
                                                      includingPropertiesForKeys: [.isDirectoryKey],
                                                      options: [.skipsHiddenFiles])) ?? []
        for dir in projectDirs {
            guard (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            let files = (try? fm.contentsOfDirectory(at: dir,
                                                    includingPropertiesForKeys: keys,
                                                    options: [.skipsHiddenFiles])) ?? []
            // Starší verze ukládají transkripty subagentů jako agent-*.jsonl vedle hlavních relací.
            for file in files where file.pathExtension == "jsonl" && !file.lastPathComponent.hasPrefix("agent-") {
                guard let values = try? file.resourceValues(forKeys: Set(keys)),
                      values.isDirectory != true,
                      let mtime = values.contentModificationDate,
                      now.timeIntervalSince(mtime) <= recentWindow else { continue }
                let size = UInt64(max(values.fileSize ?? 0, 0))
                found[file.path] = FileStamp(mtime: mtime, size: size)
            }
        }
        candidates = found
    }

    /// Mezi úplnými průchody jen přečte razítka známých souborů.
    private func quickScan() {
        for path in Array(candidates.keys) {
            if let s = stamp(atPath: path) {
                candidates[path] = s
            } else {
                candidates.removeValue(forKey: path)
            }
        }
    }

    /// Přidá transkripty, o kterých víme z hooků nebo z registru, ale sken je (ještě) nenašel.
    private func addExtraCandidates(registry: [String: RegistryEntry]) {
        var extra: [String] = []
        for state in hookStates.values {
            if let path = state.transcriptPath, !path.isEmpty { extra.append(path) }
        }
        for entry in registry.values where entry.alive {
            if let cwd = entry.cwd, !cwd.isEmpty {
                let encoded = Self.encodeProjectPath(cwd)
                extra.append(projectsDir.appendingPathComponent(encoded)
                    .appendingPathComponent(entry.sessionId + ".jsonl").path)
            }
        }
        for path in extra where candidates[path] == nil {
            if let s = stamp(atPath: path) { candidates[path] = s }
        }
    }

    /// Claude Code kóduje cestu projektu nahrazením ne-alfanumerických znaků pomlčkou.
    private static func encodeProjectPath(_ path: String) -> String {
        String(path.map { ($0.isASCII && ($0.isLetter || $0.isNumber)) ? $0 : "-" })
    }

    private func refreshTranscripts() {
        for (path, stamp) in candidates {
            if let cached = transcripts[path], cached.stamp == stamp { continue }
            transcripts[path] = parseTranscript(path: path, stamp: stamp, previous: transcripts[path])
        }
        // Úklid cache.
        for path in Array(transcripts.keys) where candidates[path] == nil {
            transcripts.removeValue(forKey: path)
        }
    }

    /// Přečte posledních `bytes` bajtů souboru a vrátí celé řádky.
    private func readTailLines(path: String, bytes: UInt64) -> [Data] {
        guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? handle.close() }
        let size = handle.seekToEndOfFile()
        let offset = size > bytes ? size - bytes : 0
        handle.seek(toFileOffset: offset)
        let data = handle.readDataToEndOfFile()
        var lines = data.split(separator: 0x0A, omittingEmptySubsequences: true).map { Data($0) }
        // První řádek je při čtení od středu souboru useknutý.
        if offset > 0, !lines.isEmpty { lines.removeFirst() }
        return lines
    }

    private func parseTranscript(path: String, stamp: FileStamp, previous: TranscriptInfo?) -> TranscriptInfo {
        var info = TranscriptInfo(stamp: stamp,
                                  cwd: previous?.cwd,
                                  branch: previous?.branch,
                                  title: previous?.title,
                                  lastPrompt: previous?.lastPrompt,
                                  lastReply: previous?.lastReply,
                                  lastKind: .unknown)
        for line in readTailLines(path: path, bytes: transcriptTailBytes) {
            guard let object = try? JSONSerialization.jsonObject(with: line),
                  let entry = object as? [String: Any] else { continue }
            if let cwd = entry["cwd"] as? String, !cwd.isEmpty { info.cwd = cwd }
            if let branch = entry["gitBranch"] as? String {
                info.branch = (branch.isEmpty || branch == "HEAD") ? nil : branch
            }
            let type = entry["type"] as? String ?? ""
            switch type {
            case "ai-title":
                if let title = entry["aiTitle"] as? String, !title.isEmpty { info.title = title }
            case "summary":
                if let summary = entry["summary"] as? String, !summary.isEmpty, info.title == nil {
                    info.title = summary
                }
            case "last-prompt":
                if let prompt = entry["lastPrompt"] as? String, let clipped = Self.clip(prompt, 80) {
                    info.lastPrompt = clipped
                }
            case "user":
                if entry["isSidechain"] as? Bool == true { continue }
                if entry["isMeta"] as? Bool == true { continue }
                let message = entry["message"] as? [String: Any]
                let content = message?["content"]
                if let text = content as? String {
                    handleUserText(text, info: &info)
                } else if let blocks = content as? [Any] {
                    var hasToolResult = false
                    var texts: [String] = []
                    for case let block as [String: Any] in blocks {
                        let blockType = block["type"] as? String
                        if blockType == "tool_result" { hasToolResult = true }
                        if blockType == "text", let t = block["text"] as? String { texts.append(t) }
                    }
                    if hasToolResult {
                        info.lastKind = .toolResult
                    } else if !texts.isEmpty {
                        handleUserText(texts.joined(separator: " "), info: &info)
                    }
                }
            case "assistant":
                if entry["isSidechain"] as? Bool == true { continue }
                let message = entry["message"] as? [String: Any]
                var hasToolUse = false
                var texts: [String] = []
                if let blocks = message?["content"] as? [Any] {
                    for case let block as [String: Any] in blocks {
                        let blockType = block["type"] as? String
                        if blockType == "tool_use" { hasToolUse = true }
                        if blockType == "text", let t = block["text"] as? String { texts.append(t) }
                    }
                } else if let text = message?["content"] as? String {
                    texts.append(text)
                }
                if let reply = Self.clip(texts.joined(separator: " "), 140) { info.lastReply = reply }
                let stopReason = message?["stop_reason"] as? String
                if hasToolUse || stopReason == "tool_use" {
                    info.lastKind = .assistantTool
                } else if !texts.isEmpty {
                    info.lastKind = .assistantText
                }
                // Bloky jen s „thinking“ stav nemění.
            default:
                break
            }
        }
        return info
    }

    private func handleUserText(_ text: String, info: inout TranscriptInfo) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return }
        if trimmed.hasPrefix("[Request interrupted") {
            info.lastKind = .interrupted
        } else if trimmed.hasPrefix("<") {
            // <command-name>, <local-command-stdout>, <system-reminder> … – ne skutečný prompt.
            info.lastKind = .command
        } else {
            info.lastPrompt = Self.clip(trimmed, 80)
            info.lastKind = .userPrompt
        }
    }

    // MARK: Události z hooků

    private func refreshHookEvents() {
        guard let s = stamp(atPath: eventsURL.path) else {
            eventsStamp = nil
            hookStates = [:]
            return
        }
        if s == eventsStamp { return }
        if s.size > eventsMaxBytes { trimEventsFile() }
        eventsStamp = stamp(atPath: eventsURL.path)

        var states: [String: HookState] = [:]
        for line in readTailLines(path: eventsURL.path, bytes: eventsTailBytes) {
            guard let object = try? JSONSerialization.jsonObject(with: line),
                  let wrapper = object as? [String: Any],
                  let event = wrapper["event"] as? [String: Any],
                  let sessionId = event["session_id"] as? String, !sessionId.isEmpty,
                  let name = event["hook_event_name"] as? String else { continue }
            let tsValue = (wrapper["ts"] as? NSNumber)?.doubleValue ?? 0
            let ts = tsValue > 0 ? Date(timeIntervalSince1970: tsValue) : Date.distantPast

            var state = states[sessionId] ?? HookState(event: name, ts: ts)
            state.event = name
            state.ts = ts
            if let cwd = event["cwd"] as? String, !cwd.isEmpty { state.cwd = cwd }
            if let path = event["transcript_path"] as? String, !path.isEmpty { state.transcriptPath = path }
            if name == "Notification" {
                state.notificationType = event["notification_type"] as? String
                state.message = event["message"] as? String
            } else {
                state.notificationType = nil
                state.message = nil
            }
            if name == "UserPromptSubmit", let prompt = event["prompt"] as? String,
               let clipped = Self.clip(prompt, 80) {
                state.prompt = clipped
            }
            states[sessionId] = state
        }
        hookStates = states
    }

    /// Udržuje soubor událostí malý: ponechá jen posledních ~512 KB.
    private func trimEventsFile() {
        let lines = readTailLines(path: eventsURL.path, bytes: 512 * 1024)
        var data = Data()
        for line in lines {
            data.append(line)
            data.append(0x0A)
        }
        try? data.write(to: eventsURL, options: .atomic)
    }

    private func refreshSettings() {
        let s = stamp(atPath: settingsURL.resolvingSymlinksInPath().path)
        if s == settingsStamp { return }
        settingsStamp = s
        hooksInstalled = ClaudeHooksInstaller.isInstalled()
    }

    // MARK: Registr běžících relací (~/.claude/sessions/<pid>.json)

    private func readRegistry() -> [String: RegistryEntry] {
        var result: [String: RegistryEntry] = [:]
        let files = (try? fm.contentsOfDirectory(at: registryDir,
                                                includingPropertiesForKeys: nil,
                                                options: [.skipsHiddenFiles])) ?? []
        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let dict = object as? [String: Any],
                  let sessionId = dict["sessionId"] as? String, !sessionId.isEmpty else { continue }
            var alive = false
            if let pid = (dict["pid"] as? NSNumber)?.int32Value, pid > 0 {
                alive = kill(pid_t(pid), 0) == 0 || errno == EPERM
            }
            let statusUpdated = Self.parseDate(dict["statusUpdatedAt"]) ?? Self.parseDate(dict["updatedAt"])
            let entry = RegistryEntry(sessionId: sessionId,
                                      cwd: dict["cwd"] as? String,
                                      status: dict["status"] as? String,
                                      statusUpdated: statusUpdated,
                                      alive: alive)
            // Při duplicitě dáme přednost živému procesu.
            if let existing = result[sessionId], existing.alive && !alive { continue }
            result[sessionId] = entry
        }
        return result
    }

    /// Čas jako číslo (ms nebo s od 1970) nebo ISO 8601 řetězec (s/bez zlomků sekund).
    private static func parseDate(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            guard raw > 0 else { return nil }
            // Hodnoty nad 1e11 jsou milisekundy.
            return Date(timeIntervalSince1970: raw > 100_000_000_000 ? raw / 1000 : raw)
        }
        guard let string = value as? String, !string.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private static func registryState(_ status: String?) -> ClaudeSessionState? {
        guard let status = status?.lowercased() else { return nil }
        if status == "busy" || status == "working" || status == "running" || status == "thinking" {
            return .working
        }
        if status.contains("wait") || status.contains("permission") || status.contains("input") || status.contains("approval") {
            return .waiting
        }
        if status == "idle" || status == "ready" || status == "done" {
            return .idle
        }
        return nil
    }

    // MARK: Sloučení zdrojů

    private func transcriptState(_ info: TranscriptInfo, now: Date) -> ClaudeSessionState {
        let age = now.timeIntervalSince(info.stamp.mtime)
        guard age <= workingWindow else { return .idle }
        switch info.lastKind {
        case .assistantText, .interrupted, .command, .unknown:
            return .idle
        case .userPrompt, .toolResult, .assistantTool:
            return .working
        }
    }

    private func buildSessions(now: Date, registry: [String: RegistryEntry]) -> [ClaudeSession] {
        var byId: [String: ClaudeSession] = [:]
        var mtimes: [String: Date] = [:]
        var lastKinds: [String: TranscriptLastKind] = [:]

        for (path, info) in transcripts {
            let id = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            let cwd = info.cwd ?? ""
            let session = ClaudeSession(id: id,
                                        projectName: Self.projectName(cwd: cwd, path: path),
                                        cwd: cwd,
                                        branch: info.branch,
                                        title: info.title,
                                        lastPrompt: info.lastPrompt,
                                        lastReply: info.lastReply,
                                        attentionMessage: nil,
                                        state: transcriptState(info, now: now),
                                        lastActivity: info.stamp.mtime,
                                        isRunning: false)
            // Stejné ID ve dvou souborech: ponech novější.
            if let existing = byId[id], existing.lastActivity >= session.lastActivity { continue }
            byId[id] = session
            mtimes[id] = info.stamp.mtime
            lastKinds[id] = info.lastKind
        }

        // Relace známé jen z hooků (transkript zatím neexistuje / je jinde).
        for (id, hook) in hookStates where byId[id] == nil {
            guard hook.event != "SessionEnd", now.timeIntervalSince(hook.ts) <= recentWindow else { continue }
            let cwd = hook.cwd ?? ""
            byId[id] = ClaudeSession(id: id,
                                     projectName: Self.projectName(cwd: cwd, path: nil),
                                     cwd: cwd,
                                     branch: nil,
                                     title: nil,
                                     lastPrompt: hook.prompt,
                                     lastReply: nil,
                                     attentionMessage: nil,
                                     state: .idle,
                                     lastActivity: hook.ts,
                                     isRunning: false)
        }

        var result: [ClaudeSession] = []
        for (id, base) in byId {
            var session = base
            let mtime = mtimes[id] ?? .distantPast
            let lastKind = lastKinds[id] ?? TranscriptLastKind.unknown
            let heuristic = session.state
            var registryTs: Date?

            // 1) Registr procesů.
            if let entry = registry[id] {
                session.isRunning = entry.alive
                if session.cwd.isEmpty, let cwd = entry.cwd, !cwd.isEmpty {
                    session.cwd = cwd
                    session.projectName = Self.projectName(cwd: cwd, path: nil)
                }
                if entry.alive, let state = Self.registryState(entry.status) {
                    session.state = state
                    if heuristic == .working && state == .idle { session.state = .working }
                    registryTs = entry.statusUpdated ?? now
                }
                if let updated = entry.statusUpdated, updated > session.lastActivity, entry.alive {
                    session.lastActivity = min(updated, now)
                }
            }

            // 2) Hooky (přesnější, pokud jsou novější než ostatní zdroje).
            if let hook = hookStates[id] {
                if hook.event == "SessionEnd" {
                    // Relace skončila; znovu ji ukážeme jen pokud se transkript později změnil.
                    if mtime.timeIntervalSince(hook.ts) <= 5 && !session.isRunning { continue }
                } else if registryTs == nil || hook.ts.timeIntervalSince(registryTs ?? .distantPast) >= -1 {
                    let resumedAfter = mtime.timeIntervalSince(hook.ts) > 3
                    switch hook.event {
                    case "UserPromptSubmit", "PreToolUse":
                        let lastSignal = max(hook.ts, mtime)
                        if lastKind == .interrupted && mtime.timeIntervalSince(hook.ts) >= 0 {
                            session.state = .idle
                        } else if now.timeIntervalSince(lastSignal) > 600 {
                            // Proces nejspíš spadl / byl přerušen bez události Stop.
                            session.state = .idle
                        } else {
                            session.state = .working
                        }
                    case "Notification":
                        let type = hook.notificationType ?? ""
                        let isAttention = !["idle_prompt", "auth_success", "agent_completed"].contains(type)
                        if resumedAfter {
                            session.state = heuristic
                        } else if isAttention {
                            session.state = .waiting
                            session.attentionMessage = hook.message.flatMap { Self.clip($0, 80) }
                        } else {
                            session.state = .idle
                        }
                    case "Stop", "SessionStart":
                        session.state = (resumedAfter && heuristic == .working) ? .working : .idle
                    default:
                        break
                    }
                }
                if let prompt = hook.prompt { session.lastPrompt = prompt }
                if session.cwd.isEmpty, let cwd = hook.cwd, !cwd.isEmpty {
                    session.cwd = cwd
                    session.projectName = Self.projectName(cwd: cwd, path: nil)
                }
                if hook.ts > session.lastActivity { session.lastActivity = min(hook.ts, now) }
            }

            guard now.timeIntervalSince(session.lastActivity) <= recentWindow || session.isRunning else { continue }
            result.append(session)
        }

        // Aktivní relace vždy, zbytek doplnit nejnovějšími nečinnými.
        result.sort { $0.lastActivity > $1.lastActivity }
        let active = result.filter { $0.state != .idle }
        let idle = result.filter { $0.state == .idle }
        var picked = Array(active.prefix(maxSessions))
        picked.append(contentsOf: idle.prefix(max(0, maxSessions - picked.count)))
        picked.sort { $0.lastActivity > $1.lastActivity }
        return picked
    }

    // MARK: Pomocné

    private static func projectName(cwd: String, path: String?) -> String {
        if !cwd.isEmpty {
            let name = URL(fileURLWithPath: cwd).lastPathComponent
            if !name.isEmpty && name != "/" { return name }
        }
        if let path {
            // Záložní varianta z kódovaného názvu složky (např. „-Users-jan-projekt“).
            let folder = URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
            if let last = folder.split(separator: "-").last, !last.isEmpty { return String(last) }
        }
        return "Claude Code"
    }

    /// Sloučí bílé znaky a zkrátí text na `limit` znaků (s výpustkou).
    static func clip(_ text: String, _ limit: Int) -> String? {
        let head = text.prefix(limit * 4)
        let collapsed = head.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        if collapsed.isEmpty { return nil }
        if collapsed.count <= limit { return collapsed }
        return String(collapsed.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

// MARK: - Instalace hooků do ~/.claude/settings.json

/// Hooky zapisují vstup (JSON ze stdin) jako jeden řádek do souboru událostí.
/// Příkaz používá jen nástroje dostupné na čistém macOS (`tr`, `date`, `printf`),
/// nevyžaduje Python ani Command Line Tools. JSON ze stdin může být víceřádkový,
/// ale řetězce v JSON nesmí obsahovat syrové konce řádků, takže `tr -d '\r\n'`
/// obsah nepoškodí. Každý řádek má tvar `{"ts":<unix sekundy>,"event":<vstup hooku>}`.
/// Hook nic nevypisuje na stdout (u UserPromptSubmit/SessionStart by se výstup
/// přidal do kontextu) a vždy končí kódem 0, takže Claude Code nikdy neblokuje.
enum ClaudeHooksInstaller {
    static let marker = "NotchMax"

    static let events: [String] = ["SessionStart", "UserPromptSubmit", "PreToolUse",
                                   "Notification", "Stop", "SessionEnd"]

    /// Události, u kterých Claude Code podporuje matcher (u ostatních se vynechává).
    private static let matcherEvents: Set<String> = ["SessionStart", "PreToolUse", "Notification", "SessionEnd"]

    static var eventsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NotchMax", isDirectory: true)
            .appendingPathComponent("claude-events.jsonl")
    }

    static var settingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    static let command: String =
        "d=\"$HOME/Library/Application Support/NotchMax\"; mkdir -p \"$d\"; "
        + "l=$(tr -d '\\r\\n'); "
        + "[ -n \"$l\" ] && printf '{\"ts\":%s,\"event\":%s}\\n' \"$(date +%s)\" \"$l\" >> \"$d/claude-events.jsonl\"; "
        + "exit 0 # NotchMax hook"

    // MARK: Stav

    static func isInstalled() -> Bool {
        guard let root = try? readSettings(), let hooks = root["hooks"] as? [String: Any] else { return false }
        for value in hooks.values {
            guard let groups = value as? [Any] else { continue }
            for case let group as [String: Any] in groups {
                guard let inner = group["hooks"] as? [Any] else { continue }
                for case let hook as [String: Any] in inner where isOurs(hook) { return true }
            }
        }
        return false
    }

    // MARK: Instalace / odinstalace

    static func install() throws {
        let fm = FileManager.default
        try? fm.createDirectory(at: eventsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: eventsURL.path) {
            fm.createFile(atPath: eventsURL.path, contents: Data())
        }

        var root = try readSettings() ?? [:]
        var hooks = removingOurs(from: root["hooks"] as? [String: Any] ?? [:])
        for event in events {
            var group: [String: Any] = [
                "hooks": [[
                    "type": "command",
                    "command": command,
                    "timeout": 5
                ] as [String: Any]]
            ]
            if matcherEvents.contains(event) { group["matcher"] = "*" }
            var groups = hooks[event] as? [Any] ?? []
            groups.append(group)
            hooks[event] = groups
        }
        root["hooks"] = hooks
        try writeSettings(root)
    }

    static func uninstall() throws {
        guard var root = try readSettings() else { return }
        guard let hooks = root["hooks"] as? [String: Any] else { return }
        let cleaned = removingOurs(from: hooks)
        if cleaned.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = cleaned
        }
        try writeSettings(root)
    }

    // MARK: Pomocné

    private static func isOurs(_ hook: [String: Any]) -> Bool {
        (hook["command"] as? String)?.contains(marker) == true
    }

    /// Odstraní jen položky obsahující „NotchMax“; prázdné skupiny a události smaže.
    private static func removingOurs(from hooks: [String: Any]) -> [String: Any] {
        var result: [String: Any] = [:]
        for (event, value) in hooks {
            guard let groups = value as? [Any] else {
                result[event] = value
                continue
            }
            var keptGroups: [Any] = []
            for item in groups {
                guard var group = item as? [String: Any], let inner = group["hooks"] as? [Any] else {
                    keptGroups.append(item)
                    continue
                }
                let keptInner = inner.filter { element in
                    guard let hook = element as? [String: Any] else { return true }
                    return !isOurs(hook)
                }
                if keptInner.isEmpty && !inner.isEmpty { continue }
                group["hooks"] = keptInner
                keptGroups.append(group)
            }
            if !keptGroups.isEmpty || groups.isEmpty {
                result[event] = keptGroups
            }
        }
        return result
    }

    /// `nil` = soubor neexistuje nebo je prázdný. Neplatný JSON → chyba (nikdy ho nepřepíšeme).
    private static func readSettings() throws -> [String: Any]? {
        let url = settingsURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ClaudeHooksError.writeFailed(error.localizedDescription)
        }
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            throw ClaudeHooksError.invalidSettings
        }
        return dict
    }

    /// Záloha (settings.json.notchmax-backup) a atomický zápis.
    private static func writeSettings(_ root: [String: Any]) throws {
        let fm = FileManager.default
        // Symlink (např. dotfiles) zachováme – zapisujeme do cílového souboru.
        let url = settingsURL.resolvingSymlinksInPath()
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: url.path) {
                let backup = url.deletingLastPathComponent()
                    .appendingPathComponent(url.lastPathComponent + ".notchmax-backup")
                let original = try Data(contentsOf: url)
                try original.write(to: backup, options: .atomic)
            }
            let data = try JSONSerialization.data(withJSONObject: root,
                                                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: url, options: .atomic)
        } catch {
            throw ClaudeHooksError.writeFailed(error.localizedDescription)
        }
    }
}
