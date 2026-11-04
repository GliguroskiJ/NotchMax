import AppKit
import Combine
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
    /// Identifikátor kalendáře (EKCalendar.calendarIdentifier).
    var calendarID: String = ""
}

/// Jeden systémový kalendář (EventKit) pro výběr v Nastavení.
struct SystemCalendarInfo: Identifiable, Equatable {
    let id: String
    let title: String
    let color: Color
}

/// Systémové kalendáře seskupené podle účtu (iCloud, Google – jovan@…, Na Macu…).
struct SystemCalendarGroup: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let calendars: [SystemCalendarInfo]
}

/// Hledání odkazu na online schůzku (Zoom, Meet, Teams, Webex) v textu události.
enum MeetingLink {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private static let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com"]

    static func find(in texts: [String]) -> URL? {
        for text in texts {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector?.matches(in: text, options: [], range: range) ?? [] {
                if let url = match.url, let host = url.host,
                   hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                    return url
                }
            }
        }
        return nil
    }
}

/// Události z kalendářů macOS přes EventKit (iCloud, Exchange, Google účet přidaný
/// v Nastavení systému → Internetové účty…).
@MainActor
final class CalendarMonitor: ObservableObject {
    enum Access { case unknown, granted, denied }

    /// Přístup k systémovým kalendářům (EventKit).
    @Published private(set) var access: Access = .unknown
    /// macOS povolil jen zápis do kalendáře – události číst nejde.
    @Published private(set) var isWriteOnly = false
    @Published private(set) var events: [CalEvent] = []
    @Published private(set) var calendarGroups: [SystemCalendarGroup] = []
    @Published private(set) var now = Date()

    private let store = EKEventStore()
    private var timer: Timer?
    private var fastTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    /// Je k dispozici zdroj událostí (přístup ke kalendářům macOS povolen).
    var hasAnySource: Bool { access == .granted }

    init() {
        refreshAccess()

        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshAccess() }
        }

        AppSettings.shared.$hiddenCalendarIDs
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.reload() }
            }
            .store(in: &cancellables)

        let tick = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.now = Date()
                self?.reload()
            }
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick

        // Kolem začátku schůzky aktualizovat `now` každou vteřinu, aby odpočet v notchi
        // nezůstal viset na „0 s“ (plný reload zůstává po 30 s).
        let fastTick = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let current = Date()
                let near = self.events.contains { e in
                    !e.isAllDay && abs(e.start.timeIntervalSince(current)) < 70
                }
                if near { self.now = current }
            }
        }
        RunLoop.main.add(fastTick, forMode: .common)
        fastTimer = fastTick
    }

    func refreshAccess() {
        let status = EKEventStore.authorizationStatus(for: .event)
        let wasGranted = access == .granted
        isWriteOnly = false
        switch status {
        case .fullAccess:
            // Pozn.: zastaralé `.authorized` má stejnou hodnotu jako `.fullAccess`, pokryje ho tento case.
            access = .granted
        case .notDetermined:
            access = .unknown
        case .writeOnly:
            isWriteOnly = true
            access = .denied
        case .denied, .restricted:
            access = .denied
        @unknown default:
            access = .denied
        }
        if access == .granted && !wasGranted {
            store.refreshSourcesIfNecessary()
        }
        reload()
    }

    /// Požádá o přístup k systémovým kalendářům. Pokud už byl dřív zamítnut,
    /// macOS dialog znovu neukáže – otevře se rovnou Soukromí v Nastavení systému.
    func requestAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            Task {
                let granted = (try? await store.requestFullAccessToEvents()) ?? false
                if granted { store.reset() }
                refreshAccess()
            }
        case .fullAccess:
            refreshAccess()
        default:
            Self.openPrivacySettings()
        }
    }

    static func openPrivacySettings() {
        SystemSettingsLink.open(.calendars)
    }

    static func openInternetAccounts() {
        SystemSettingsLink.open(.internetAccounts)
    }

    func reload() {
        let hidden = Set(AppSettings.shared.hiddenCalendarIDs)
        let current = Date()

        // Systémové kalendáře (EventKit)
        var systemEvents: [CalEvent] = []
        if access == .granted {
            let allCalendars = store.calendars(for: .event)
            updateGroups(allCalendars)
            let visible = allCalendars.filter { !hidden.contains($0.calendarIdentifier) }
            let cal = Calendar.current
            let start = cal.startOfDay(for: current)
            // Prázdné pole by EventKit bral jako „všechny kalendáře“ – proto ho vůbec nedotazujeme.
            if !visible.isEmpty, let end = cal.date(byAdding: .day, value: 2, to: start) {
                let predicate = store.predicateForEvents(withStart: start, end: end, calendars: visible)
                systemEvents = store.events(matching: predicate).map { e in
                    let color = e.calendar.flatMap { NSColor(cgColor: $0.cgColor) } ?? NSColor.systemBlue
                    return CalEvent(
                        id: "\(e.eventIdentifier ?? UUID().uuidString)-\(e.startDate.timeIntervalSince1970)",
                        title: e.title ?? L("Bez názvu"),
                        start: e.startDate,
                        end: e.endDate,
                        isAllDay: e.isAllDay,
                        color: Color(nsColor: color),
                        location: e.location,
                        joinURL: Self.joinURL(for: e),
                        calendarID: e.calendar?.calendarIdentifier ?? ""
                    )
                }
            }
        } else if !calendarGroups.isEmpty {
            calendarGroups = []
        }

        let merged = systemEvents
            .filter { $0.end > current }
            .sorted { lhs, rhs in
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                return lhs.title < rhs.title
            }
        if merged != events { events = merged }
    }

    private func updateGroups(_ calendars: [EKCalendar]) {
        var bySource: [String: (source: EKSource?, items: [EKCalendar])] = [:]
        for calendar in calendars {
            let key = calendar.source?.sourceIdentifier ?? "local"
            var entry = bySource[key] ?? (source: calendar.source, items: [])
            entry.items.append(calendar)
            bySource[key] = entry
        }
        let groups: [SystemCalendarGroup] = bySource.map { element -> SystemCalendarGroup in
            let key = element.key
            let entry = element.value
            let infos = entry.items
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                .map { cal in
                    SystemCalendarInfo(
                        id: cal.calendarIdentifier,
                        title: cal.title,
                        color: Color(nsColor: NSColor(cgColor: cal.cgColor) ?? NSColor.systemBlue)
                    )
                }
            return SystemCalendarGroup(
                id: key,
                title: Self.sourceTitle(entry.source),
                subtitle: Self.sourceKind(entry.source),
                calendars: infos
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        if groups != calendarGroups { calendarGroups = groups }
    }

    private static func sourceTitle(_ source: EKSource?) -> String {
        guard let source else { return L("Ostatní") }
        let title = source.title
        let lower = title.lowercased()
        if lower.contains("gmail") || lower.contains("googlemail") || lower == "google" {
            return "Google – \(title)"
        }
        switch source.sourceType {
        case .local: return L("Na tomto Macu")
        case .birthdays: return L("Narozeniny")
        case .subscribed: return L("Odebírané kalendáře")
        default: return title.isEmpty ? L("Účet") : title
        }
    }

    private static func sourceKind(_ source: EKSource?) -> String {
        guard let source else { return "" }
        switch source.sourceType {
        case .local: return L("Místní")
        case .exchange: return "Exchange"
        case .calDAV: return source.title.lowercased().contains("icloud") ? "iCloud" : "CalDAV"
        case .mobileMe: return "iCloud"
        case .subscribed: return L("Odběr")
        case .birthdays: return L("Kontakty")
        @unknown default: return ""
        }
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
        MeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes].compactMap { $0 })
    }
}
