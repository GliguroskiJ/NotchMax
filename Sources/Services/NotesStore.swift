import Foundation
import SwiftUI

// MARK: - Rychlé poznámky: model a úložiště

struct Note: Identifiable, Codable, Equatable {
    var id: UUID
    var text: String
    var pinned: Bool
    var created: Date
    var updated: Date
}

/// Úložiště poznámek. Perzistence: JSON v ~/Library/Application Support/NotchMax/notes.json
/// (zápis atomicky, s odložením ~0,5 s).
@MainActor
final class NotesStore: ObservableObject {
    static let shared = NotesStore()

    /// Seřazeno: připnuté nahoře, pak podle `updated` sestupně.
    @Published private(set) var notes: [Note] = []

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    private init() {
        let base: URL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        fileURL = base
            .appendingPathComponent("NotchMax", isDirectory: true)
            .appendingPathComponent("notes.json", isDirectory: false)
        load()
    }

    // MARK: Úpravy

    func add(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let now = Date()
        let note = Note(id: UUID(), text: trimmed, pinned: false, created: now, updated: now)
        var list = notes
        list.append(note)
        notes = Self.sorted(list)
        scheduleSave()
    }

    /// Prázdný text poznámku smaže.
    func update(_ id: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        if trimmed.isEmpty {
            delete(id)
            return
        }
        guard notes[index].text != trimmed else { return }
        var list = notes
        list[index].text = trimmed
        list[index].updated = Date()
        notes = Self.sorted(list)
        scheduleSave()
    }

    func togglePin(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        var list = notes
        list[index].pinned.toggle()
        notes = Self.sorted(list)
        scheduleSave()
    }

    func delete(_ id: UUID) {
        guard notes.contains(where: { $0.id == id }) else { return }
        notes = notes.filter { $0.id != id }
        scheduleSave()
    }

    // MARK: Řazení

    private static func sorted(_ list: [Note]) -> [Note] {
        list.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.updated > b.updated
        }
    }

    // MARK: Perzistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([Note].self, from: data)
            notes = Self.sorted(decoded)
        } catch {
            NSLog("NotchMax: načtení poznámek selhalo: \(error.localizedDescription)")
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.writeToDisk()
        }
    }

    private func writeToDisk() {
        do {
            let folder = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(notes)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("NotchMax: uložení poznámek selhalo: \(error.localizedDescription)")
        }
    }
}
