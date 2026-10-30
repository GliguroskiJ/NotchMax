import AppKit
import Combine
import UniformTypeIdentifiers

struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let added: Date
    var name: String { url.lastPathComponent }
}

/// Odkladiště souborů: soubory se kopírují do Application Support/NotchMax/Shelf,
/// takže přežijí přesun či smazání originálu. Staré položky se mažou podle nastavení.
@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    private let root: URL
    private var purgeTimer: Timer?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = base.appendingPathComponent("NotchMax/Shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        load()
        purgeExpired()
        let timer = Timer(timeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.purgeExpired() }
        }
        RunLoop.main.add(timer, forMode: .common)
        purgeTimer = timer
    }

    // MARK: - Přidání

    func add(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { @Sendable item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let u = item as? URL {
                    url = u
                }
                guard let url else { return }
                Task { @MainActor [weak self] in self?.ingest(url) }
            }
        }
    }

    /// Kopírování běží mimo hlavní vlákno (velké soubory a složky by jinak zamrazily notch).
    private func ingest(_ source: URL) {
        let id = UUID()
        let dir = root.appendingPathComponent(id.uuidString, isDirectory: true)
        let dest = dir.appendingPathComponent(source.lastPathComponent)
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: dest)
                await MainActor.run {
                    self?.items.insert(ShelfItem(id: id, url: dest, added: Date()), at: 0)
                }
            } catch {
                NSLog("NotchMax shelf: \(error.localizedDescription)")
                try? FileManager.default.removeItem(at: dir)
            }
        }
    }

    // MARK: - Odebrání

    func remove(_ item: ShelfItem) {
        try? FileManager.default.removeItem(at: item.url.deletingLastPathComponent())
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        for item in items {
            try? FileManager.default.removeItem(at: item.url.deletingLastPathComponent())
        }
        items.removeAll()
    }

    func airDrop(_ list: [ShelfItem]) {
        guard !list.isEmpty else { return }
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: list.map { $0.url })
    }

    // MARK: - Údržba

    private func load() {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey]) else { return }
        var loaded: [ShelfItem] = []
        for dir in dirs {
            guard let id = UUID(uuidString: dir.lastPathComponent),
                  let file = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))?.first
            else { continue }
            let created = (try? dir.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()
            loaded.append(ShelfItem(id: id, url: file, added: created))
        }
        items = loaded.sorted { $0.added > $1.added }
    }

    func purgeExpired() {
        let ttl = AppSettings.shared.shelfTTLHours
        guard ttl > 0 else { return }
        let limit = Date().addingTimeInterval(-Double(ttl) * 3600)
        for item in items where item.added < limit {
            remove(item)
        }
    }
}
