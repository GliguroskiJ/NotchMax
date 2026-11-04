import Foundation
import SwiftUI

/// Spouštěč Apple Shortcuts přes `/usr/bin/shortcuts` (bez shellu, argumenty jako pole).
@MainActor
final class ShortcutsStore: ObservableObject {
    static let shared = ShortcutsStore()

    /// Názvy zkratek uživatele (seřazené).
    @Published private(set) var shortcuts: [String] = []
    /// `true`, jakmile se seznam aspoň jednou úspěšně načetl.
    @Published private(set) var hasLoaded = false
    @Published private(set) var isReloading = false
    @Published private(set) var runningName: String?
    @Published private(set) var lastError: String?

    private var errorTask: Task<Void, Never>?

    private init() {}

    /// Existuje zkratka daného názvu? (Má smysl jen po načtení, viz `hasLoaded`.)
    func contains(_ name: String) -> Bool {
        shortcuts.contains(name)
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
                self.hasLoaded = true
            } else {
                self.shortcuts = []
                self.showError("Zkratky se nepodařilo načíst")
            }
        }
    }

    /// Spustí zkratku podle názvu (s UI stavem `runningName` / `lastError`).
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
                self.showError(ShortcutsStore.errorMessage(for: result))
            }
        }
    }

    /// Spustí zkratku na pozadí bez zásahu do UI stavu. Při chybě zavolá `onFailure`
    /// (na hlavním vlákně) s krátkým popisem.
    func runSilently(_ name: String, onFailure: (@MainActor (String) -> Void)? = nil) {
        Task {
            let result: ExecResult = await Task.detached {
                ShortcutsStore.exec(["run", name])
            }.value
            if result.status != 0 {
                onFailure?(ShortcutsStore.errorMessage(for: result))
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

    nonisolated private static func errorMessage(for result: ExecResult) -> String {
        let firstLine: String = result.errorOutput
            .components(separatedBy: "\n")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if firstLine.isEmpty {
            return "Zkratka selhala (kód \(result.status))"
        }
        return String(firstLine.prefix(70))
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
