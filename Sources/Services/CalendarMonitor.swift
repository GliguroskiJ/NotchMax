import EventKit
import SwiftUI

struct CalEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    let location: String?
    let joinURL: URL?
}

/// Události přes EventKit. Google účet přidaný v Nastavení macOS (Internetové účty)
/// se tu objeví automaticky, bez vlastního OAuth.
@MainActor
final class CalendarMonitor: ObservableObject {
    enum Access { case unknown, granted, denied }

    @Published private(set) var access: Access = .unknown
    @Published private(set) var events: [CalEvent] = []
    @Published private(set) var now = Date()

    private let store = EKEventStore()
    private var timer: Timer?
    private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    init() {
        refreshAccess()
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        let tick = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.now = Date()
                self?.reload()
            }
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    func refreshAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            access = .granted
            reload()
        case .notDetermined:
            access = .unknown
        default:
            access = .denied
        }
    }

    func requestAccess() {
        Task {
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            access = granted ? .granted : .denied
            if granted { reload() }
        }
    }

    func reload() {
        guard access == .granted else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        guard let end = cal.date(byAdding: .day, value: 2, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let current = Date()
        let mapped: [CalEvent] = store.events(matching: predicate)
            .filter { $0.endDate > current }
            .sorted { $0.startDate < $1.startDate }
            .map { e in
                let color = e.calendar.flatMap { NSColor(cgColor: $0.cgColor) } ?? NSColor.systemBlue
                return CalEvent(
                    id: "\(e.eventIdentifier ?? UUID().uuidString)-\(e.startDate.timeIntervalSince1970)",
                    title: e.title ?? "Bez názvu",
                    start: e.startDate,
                    end: e.endDate,
                    isAllDay: e.isAllDay,
                    color: Color(nsColor: color),
                    location: e.location,
                    joinURL: Self.joinURL(for: e)
                )
            }
        if mapped != events { events = mapped }
    }

    /// Nejbližší (nebo právě probíhající) událost s časem.
    var nextEvent: CalEvent? {
        events.first { !$0.isAllDay && $0.end > now } ?? events.first
    }

    /// Za kolik minut začíná nejbližší událost (nil, pokud žádná v budoucnu nezačíná).
    var minutesToNext: Int? {
        guard let e = events.first(where: { !$0.isAllDay && $0.start > now }) else { return nil }
        return Int(ceil(e.start.timeIntervalSince(now) / 60))
    }

    private static func joinURL(for event: EKEvent) -> URL? {
        let texts = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }
        let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com"]
        for text in texts {
            let range = NSRange(text.startIndex..., in: text)
            for match in Self.linkDetector?.matches(in: text, options: [], range: range) ?? [] {
                if let url = match.url, let host = url.host,
                   hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                    return url
                }
            }
        }
        return nil
    }
}
