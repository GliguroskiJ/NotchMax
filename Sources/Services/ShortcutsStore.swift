import Foundation
import SwiftUI

/// Spouštěč Apple Shortcuts přes `/usr/bin/shortcuts` (bez shellu, argumenty jako pole).
@MainActor
final class ShortcutsStore: ObservableObject {
    static let shared = ShortcutsStore()

    @Published private(set) var shortcuts: [String] = []
    @Published private(set) var runningName: String?
    @Published private(set) var lastError: String?
    /// Připnuté zkratky (v pořadí připnutí), uložené v UserDefaults.
    @Published private(set) var pinned: [String] = []

    private static let pinnedKey = "pinnedShortcuts"
    private var errorTask: Task<Void, Never>?
    private var isReloading = false

    private init() {
        pinned = UserDefaults.standard.stringArray(forKey: ShortcutsStore.pinnedKey) ?? []
    }

    /// Seznam k zobrazení: nejdřív připnuté (které existují), pak ostatní.
    var orderedShortcuts: [String] {
        let pinnedExisting: [String] = pinned.filter { shortcuts.contains($0) }
        let rest: [String] = shortcuts.filter { !pinned.contains($0) }
        return pinnedExisting + rest
    }

    func isPinned(_ name: String) -> Bool {
        pinned.contains(name)
    }

    func togglePin(_ name: String) {
        if let index = pinned.firstIndex(of: name) {
            pinned.remove(at: index)
        } else {
            pinned.append(name)
        }
        UserDefaults.standard.set(pinned, forKey: ShortcutsStore.pinnedKey)
    }

    /// Načte názvy zkratek na pozadí.
    func reload() {
        if isReloading { return }
        isReloading = true
        Task {
            let result: ExecResult = await Task.detached {
                ShortcutsStore.exec(["list"])
            }.value
            self.isReloading = false
            if result.status == 0 {
                let lines: [String] = result.output
                    .components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                self.shortcuts = lines.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            } else {
                self.shortcuts = []
                self.showError("Zkratky se nepodařilo načíst")
            }
        }
    }

    /// Spustí zkratku podle názvu.
    func run(_ name: String) {
        if runningName != nil { return }
        runningName = name
        lastError = nil
        errorTask?.cancel()
        Task {
            let result: ExecResult = await Task.detached {
                ShortcutsStore.exec(["run", name])
            }.value
            self.runningName = nil
            if result.status != 0 {
                let firstLine: String = result.errorOutput
                    .components(separatedBy: "\n")
                    .first?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if firstLine.isEmpty {
                    self.showError("Zkratka selhala (kód \(result.status))")
                } else {
                    self.showError(String(firstLine.prefix(70)))
                }
            }
        }
    }

    // MARK: - Interní

    private func showError(_ text: String) {
        lastError = text
        errorTask?.cancel()
        errorTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled {
                self.lastError = nil
            }
        }
    }

    private struct ExecResult: Sendable {
        let status: Int32
        let output: String
        let errorOutput: String
    }

    /// Synchronní spuštění `shortcuts` s argumenty; volat mimo hlavní vlákno.
    nonisolated private static func exec(_ arguments: [String]) -> ExecResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = arguments
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ExecResult(status: -1, output: "", errorOutput: "Nelze spustit shortcuts")
        }
        // Čtení do EOF před waitUntilExit, aby se plná roura nezablokovala.
        let outData: Data = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData: Data = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ExecResult(
            status: process.terminationStatus,
            output: String(decoding: outData, as: UTF8.self),
            errorOutput: String(decoding: errData, as: UTF8.self)
        )
    }
}
