import AppKit
import CryptoKit
import Darwin
import Foundation
import Security
import SwiftUI

// MARK: - Chyby

enum GoogleCalendarError: LocalizedError {
    case message(String)
    case http(status: Int, code: String?, message: String?)

    var errorDescription: String? {
        switch self {
        case .message(let text):
            return text
        case .http(let status, let code, let message):
            let detail = [code, message].compactMap { $0 }.joined(separator: ": ")
            return detail.isEmpty ? "Google vrátil chybu \(status)." : "Google vrátil chybu \(status) (\(detail))."
        }
    }

    /// Refresh token už neplatí (odvolaný přístup, vypršelý testovací režim aplikace…).
    var isInvalidGrant: Bool {
        if case .http(_, let code, _) = self { return code == "invalid_grant" }
        return false
    }

    var isUnauthorized: Bool {
        if case .http(let status, _, _) = self { return status == 401 }
        return false
    }
}

// MARK: - Služba

/// Přímé napojení na Google Calendar API (OAuth 2.0 pro desktopové aplikace: PKCE + loopback redirect).
/// Uživatel si v Google Cloud Console vytvoří vlastního OAuth klienta typu „Desktop app“
/// a vloží jeho Client ID a Client secret do Nastavení → Kalendář.
@MainActor
final class GoogleCalendarService: ObservableObject {
    static let shared = GoogleCalendarService()

    struct CalendarInfo: Identifiable, Equatable {
        let id: String
        let title: String
        let color: Color
        let isPrimary: Bool
    }

    /// Klíč, pod kterým se skrytý Google kalendář ukládá do `AppSettings.hiddenCalendarIDs`.
    static func hiddenKey(for calendarID: String) -> String { "google:" + calendarID }

    @Published var clientID: String {
        didSet { UserDefaults.standard.set(clientID, forKey: Keys.clientID) }
    }
    @Published var clientSecret: String {
        didSet { UserDefaults.standard.set(clientSecret, forKey: Keys.clientSecret) }
    }
    @Published private(set) var email: String?
    @Published private(set) var isSignedIn = false
    @Published private(set) var isSigningIn = false
    @Published private(set) var isSyncing = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastSync: Date?
    @Published private(set) var calendars: [CalendarInfo] = []
    @Published private(set) var events: [CalEvent] = []

    private enum Keys {
        static let clientID = "googleOAuthClientID"
        static let clientSecret = "googleOAuthClientSecret"
        static let email = "googleAccountEmail"
        static let keychainService = "com.jovan.NotchMax.google"
        static let keychainAccount = "refreshToken"
    }

    private enum Endpoint {
        static let auth = "https://accounts.google.com/o/oauth2/v2/auth"
        static let token = "https://oauth2.googleapis.com/token"
        static let revoke = "https://oauth2.googleapis.com/revoke"
        static let userInfo = "https://www.googleapis.com/oauth2/v3/userinfo"
        static let calendarList = "https://www.googleapis.com/calendar/v3/users/me/calendarList"
        static let calendars = "https://www.googleapis.com/calendar/v3/calendars/"
    }

    private static let scopes = "openid email https://www.googleapis.com/auth/calendar.readonly"
    private static let pollInterval: TimeInterval = 5 * 60

    private var accessToken: String?
    private var accessTokenExpiry = Date.distantPast
    private var pollTimer: Timer?
    private var loopback: OAuthLoopbackServer?
    private var signInTask: Task<Void, Never>?

    private init() {
        let d = UserDefaults.standard
        clientID = d.string(forKey: Keys.clientID) ?? ""
        clientSecret = d.string(forKey: Keys.clientSecret) ?? ""
        email = d.string(forKey: Keys.email)
        if !clientID.isEmpty,
           Keychain.read(service: Keys.keychainService, account: Keys.keychainAccount) != nil {
            isSignedIn = true
            startPolling()
            Task { await self.refresh() }
        }
    }

    var hasCredentials: Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !clientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Přihlášení

    func signIn() {
        guard !isSigningIn else { return }
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !secret.isEmpty else {
            lastError = "Vlož Client ID i Client secret z Google Cloud Console."
            return
        }
        if id != clientID { clientID = id }
        if secret != clientSecret { clientSecret = secret }
        lastError = nil
        isSigningIn = true
        signInTask = Task { [weak self] in
            await self?.performSignIn(clientID: id, clientSecret: secret)
        }
    }

    func cancelSignIn() {
        loopback?.cancel()
        signInTask?.cancel()
    }

    private func performSignIn(clientID: String, clientSecret: String) async {
        defer {
            isSigningIn = false
            loopback = nil
            signInTask = nil
        }
        do {
            let server = try OAuthLoopbackServer()
            loopback = server
            let redirectURI = "http://127.0.0.1:\(server.port)"
            let verifier = Self.randomURLSafeString(byteCount: 48)
            let state = Self.randomURLSafeString(byteCount: 16)

            guard var components = URLComponents(string: Endpoint.auth) else {
                throw GoogleCalendarError.message("Neplatná adresa přihlášení.")
            }
            components.queryItems = [
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "redirect_uri", value: redirectURI),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: Self.scopes),
                URLQueryItem(name: "code_challenge", value: Self.codeChallenge(for: verifier)),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent")
            ]
            guard let authURL = components.url else {
                throw GoogleCalendarError.message("Neplatná adresa přihlášení.")
            }
            NSWorkspace.shared.open(authURL)

            let params = try await server.waitForCallback(timeout: 300)
            if let error = params["error"] {
                throw GoogleCalendarError.message(error == "access_denied"
                    ? "Přihlášení bylo zrušeno."
                    : "Přihlášení se nepovedlo (\(error)).")
            }
            guard params["state"] == state else {
                throw GoogleCalendarError.message("Neplatná odpověď z prohlížeče (state nesouhlasí).")
            }
            guard let code = params["code"], !code.isEmpty else {
                throw GoogleCalendarError.message("Google nevrátil autorizační kód.")
            }

            let data = try await postForm(Endpoint.token, [
                "code": code,
                "client_id": clientID,
                "client_secret": clientSecret,
                "redirect_uri": redirectURI,
                "grant_type": "authorization_code",
                "code_verifier": verifier
            ])
            let token = try JSONDecoder().decode(TokenResponse.self, from: data)
            guard let refreshToken = token.refresh_token, !refreshToken.isEmpty else {
                throw GoogleCalendarError.message("Google nevrátil refresh token. Zkus to znovu.")
            }
            guard Keychain.save(refreshToken, service: Keys.keychainService, account: Keys.keychainAccount) else {
                throw GoogleCalendarError.message("Nepodařilo se uložit přihlášení do Klíčenky.")
            }
            accessToken = token.access_token
            accessTokenExpiry = Date().addingTimeInterval(TimeInterval(token.expires_in ?? 3600) - 60)
            isSignedIn = true
            lastError = nil

            if let mail = try? await fetchEmail() {
                email = mail
                UserDefaults.standard.set(mail, forKey: Keys.email)
            }
            startPolling()
            NSApp.activate(ignoringOtherApps: true)
            await refresh()
        } catch is CancellationError {
            lastError = nil
        } catch let error as URLError where error.code == .cancelled {
            lastError = nil
        } catch {
            lastError = Self.describe(error)
        }
    }

    func signOut() {
        cancelSignIn()
        if let refresh = Keychain.read(service: Keys.keychainService, account: Keys.keychainAccount) {
            // Odvolání tokenu u Googlu – nejlepší snaha, výsledek nás nezajímá.
            Task { _ = try? await self.postForm(Endpoint.revoke, ["token": refresh]) }
        }
        clearSession()
        lastError = nil
    }

    private func clearSession() {
        Keychain.delete(service: Keys.keychainService, account: Keys.keychainAccount)
        UserDefaults.standard.removeObject(forKey: Keys.email)
        accessToken = nil
        accessTokenExpiry = .distantPast
        pollTimer?.invalidate()
        pollTimer = nil
        email = nil
        isSignedIn = false
        calendars = []
        events = []
        lastSync = nil
    }

    // MARK: Synchronizace

    private func startPolling() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func refreshNow() {
        Task { await refresh() }
    }

    /// Obnoví data, pokud poslední synchronizace proběhla před víc než minutou.
    func refreshIfStale() {
        guard isSignedIn else { return }
        if let last = lastSync, Date().timeIntervalSince(last) < 60 { return }
        refreshNow()
    }

    func refresh() async {
        guard isSignedIn, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let entries = try await fetchCalendarList()
            let infos = entries.map { entry in
                CalendarInfo(
                    id: entry.id,
                    title: entry.summaryOverride ?? entry.summary ?? entry.id,
                    color: Self.color(hex: entry.backgroundColor),
                    isPrimary: entry.primary ?? false
                )
            }
            .sorted { lhs, rhs in
                if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

            let cal = Calendar.current
            let start = cal.startOfDay(for: Date())
            let end = cal.date(byAdding: .day, value: 2, to: start) ?? start.addingTimeInterval(2 * 86400)

            var collected: [CalEvent] = []
            var firstError: Error?
            for info in infos {
                do {
                    collected += try await fetchEvents(calendar: info, from: start, to: end)
                } catch {
                    if let gErr = error as? GoogleCalendarError, gErr.isInvalidGrant { throw gErr }
                    if firstError == nil { firstError = error }
                }
            }
            collected.sort { $0.start < $1.start }

            // Během stahování se uživatel mohl odhlásit – nepřepisovat vyčištěný stav.
            guard isSignedIn else { return }
            if infos != calendars { calendars = infos }
            if collected != events { events = collected }
            lastSync = Date()
            lastError = firstError.map { Self.describe($0) }

            if email == nil, let mail = try? await fetchEmail() {
                email = mail
                UserDefaults.standard.set(mail, forKey: Keys.email)
            }
        } catch let error as GoogleCalendarError where error.isInvalidGrant {
            clearSession()
            lastError = "Přihlášení ke Googlu vypršelo nebo bylo odvoláno. Přihlas se prosím znovu."
        } catch {
            lastError = Self.describe(error)
        }
    }

    // MARK: Google API

    private func fetchEmail() async throws -> String? {
        guard let url = URL(string: Endpoint.userInfo) else { return nil }
        let data = try await authorizedGET(url)
        return try JSONDecoder().decode(UserInfo.self, from: data).email
    }

    private func fetchCalendarList() async throws -> [CalendarListEntry] {
        var all: [CalendarListEntry] = []
        var pageToken: String?
        repeat {
            guard var components = URLComponents(string: Endpoint.calendarList) else { break }
            var items = [URLQueryItem(name: "maxResults", value: "250")]
            if let pageToken { items.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            components.queryItems = items
            // URLComponents nekóduje „+“, Google by ho v pageTokenu četl jako mezeru.
            components.percentEncodedQuery = components.percentEncodedQuery?
                .replacingOccurrences(of: "+", with: "%2B")
            guard let url = components.url else { break }
            let data = try await authorizedGET(url)
            let response = try JSONDecoder().decode(CalendarListResponse.self, from: data)
            // Kalendáře jen s přístupem „volno/obsazeno“ nemají názvy událostí – vynecháme je.
            all += (response.items ?? []).filter { $0.deleted != true && $0.accessRole != "freeBusyReader" }
            pageToken = response.nextPageToken
        } while pageToken != nil
        return all
    }

    private func fetchEvents(calendar: CalendarInfo, from start: Date, to end: Date) async throws -> [CalEvent] {
        let encodedID = calendar.id.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? calendar.id
        guard var components = URLComponents(string: Endpoint.calendars + encodedID + "/events") else { return [] }
        let iso = ISO8601DateFormatter()
        components.queryItems = [
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "timeMin", value: iso.string(from: start)),
            URLQueryItem(name: "timeMax", value: iso.string(from: end)),
            URLQueryItem(name: "maxResults", value: "250")
        ]
        guard let url = components.url else { return [] }
        let data = try await authorizedGET(url)
        let response = try JSONDecoder().decode(EventsResponse.self, from: data)

        return (response.items ?? []).compactMap { item -> CalEvent? in
            if item.status == "cancelled" { return nil }
            if item.eventType == "workingLocation" { return nil }
            if item.attendees?.contains(where: { $0.isSelf == true && $0.responseStatus == "declined" }) == true {
                return nil
            }
            guard let startTime = item.start, let endTime = item.end,
                  let parsedStart = Self.parse(startTime) else { return nil }
            let isAllDay = startTime.date != nil && startTime.dateTime == nil
            let parsedEnd = Self.parse(endTime) ?? parsedStart
            return CalEvent(
                id: "g-\(calendar.id)-\(item.id)",
                title: (item.summary?.isEmpty == false ? item.summary : nil) ?? "Bez názvu",
                start: parsedStart,
                end: parsedEnd,
                isAllDay: isAllDay,
                color: calendar.color,
                location: item.location,
                joinURL: Self.joinURL(for: item),
                calendarID: calendar.id
            )
        }
    }

    // MARK: HTTP

    private func authorizedGET(_ url: URL) async throws -> Data {
        do {
            return try await get(url, token: try await validAccessToken())
        } catch let error as GoogleCalendarError where error.isUnauthorized {
            // Access token mohl být zneplatněn dřív, než vypršel – jednou zkusíme nový.
            return try await get(url, token: try await validAccessToken(forceRefresh: true))
        }
    }

    private func get(_ url: URL, token: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data)
        return data
    }

    private func postForm(_ endpoint: String, _ params: [String: String]) async throws -> Data {
        guard let url = URL(string: endpoint) else {
            throw GoogleCalendarError.message("Neplatná adresa \(endpoint).")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(params).data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data)
        return data
    }

    private func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh, let token = accessToken, Date() < accessTokenExpiry { return token }
        guard let refreshToken = Keychain.read(service: Keys.keychainService, account: Keys.keychainAccount) else {
            throw GoogleCalendarError.http(status: 400, code: "invalid_grant", message: "Chybí refresh token.")
        }
        let data = try await postForm(Endpoint.token, [
            "client_id": clientID.trimmingCharacters(in: .whitespacesAndNewlines),
            "client_secret": clientSecret.trimmingCharacters(in: .whitespacesAndNewlines),
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ])
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = token.access_token
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(token.expires_in ?? 3600) - 60)
        if let newRefresh = token.refresh_token, !newRefresh.isEmpty, newRefresh != refreshToken {
            Keychain.save(newRefresh, service: Keys.keychainService, account: Keys.keychainAccount)
        }
        return token.access_token
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200..<300).contains(http.statusCode) else { return }
        var code: String?
        var message: String?
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? String {
                // OAuth endpointy: {"error": "invalid_grant", "error_description": "…"}
                code = error
                message = object["error_description"] as? String
            } else if let error = object["error"] as? [String: Any] {
                // Calendar API: {"error": {"code": 403, "message": "…", "status": "PERMISSION_DENIED"}}
                code = error["status"] as? String
                message = error["message"] as? String
            }
        }
        throw GoogleCalendarError.http(status: http.statusCode, code: code, message: message)
    }

    private static func describe(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "Bez připojení k internetu."
            case .timedOut:
                return "Google neodpověděl včas."
            default:
                return urlError.localizedDescription
            }
        }
        if let gErr = error as? GoogleCalendarError {
            if case .http(_, let code, _) = gErr, code == "invalid_client" {
                return "Neplatné Client ID nebo Client secret."
            }
            if case .http(_, let code, _) = gErr, code == "PERMISSION_DENIED" {
                return "Google Calendar API není v projektu povolené, nebo chybí oprávnění. \(gErr.localizedDescription)"
            }
            return gErr.localizedDescription
        }
        if error is DecodingError {
            return "Neočekávaná odpověď od Googlu."
        }
        return error.localizedDescription
    }

    // MARK: Pomocné funkce

    /// RFC 3986 „unreserved“ – jen ASCII (`CharacterSet.alphanumerics` obsahuje i ne-ASCII písmena,
    /// která by zůstala nezakódovaná a URL by pak nešlo sestavit).
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    private static func formEncode(_ params: [String: String]) -> String {
        params.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? value
            return "\(k)=\(v)"
        }
        .joined(separator: "&")
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        }
        return base64URL(Data(bytes))
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func parse(_ time: GEventTime) -> Date? {
        if let dateTime = time.dateTime {
            let plain = ISO8601DateFormatter()
            if let date = plain.date(from: dateTime) { return date }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return fractional.date(from: dateTime)
        }
        if let day = time.date {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: day)
        }
        return nil
    }

    private static func color(hex: String?) -> Color {
        guard var text = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return Color.blue
        }
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return Color.blue }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    private static func joinURL(for event: GEvent) -> URL? {
        if let link = event.hangoutLink, let url = URL(string: link) { return url }
        if let video = event.conferenceData?.entryPoints?.first(where: { $0.entryPointType == "video" }),
           let uri = video.uri, let url = URL(string: uri) {
            return url
        }
        return MeetingLink.find(in: [event.location, event.description].compactMap { $0 })
    }
}

// MARK: - JSON modely Google API

private struct TokenResponse: Decodable {
    let access_token: String
    let expires_in: Int?
    let refresh_token: String?
}

private struct UserInfo: Decodable {
    let email: String?
}

private struct CalendarListResponse: Decodable {
    let items: [CalendarListEntry]?
    let nextPageToken: String?
}

private struct CalendarListEntry: Decodable {
    let id: String
    let summary: String?
    let summaryOverride: String?
    let backgroundColor: String?
    let primary: Bool?
    let deleted: Bool?
    let accessRole: String?
}

private struct EventsResponse: Decodable {
    let items: [GEvent]?
}

private struct GEvent: Decodable {
    let id: String
    let status: String?
    let summary: String?
    let location: String?
    let description: String?
    let hangoutLink: String?
    let eventType: String?
    let start: GEventTime?
    let end: GEventTime?
    let conferenceData: GConferenceData?
    let attendees: [GAttendee]?
}

private struct GEventTime: Decodable {
    let date: String?
    let dateTime: String?
}

private struct GConferenceData: Decodable {
    let entryPoints: [GEntryPoint]?
}

private struct GEntryPoint: Decodable {
    let entryPointType: String?
    let uri: String?
}

private struct GAttendee: Decodable {
    let isSelf: Bool?
    let responseStatus: String?

    enum CodingKeys: String, CodingKey {
        case isSelf = "self"
        case responseStatus
    }
}

// MARK: - Lokální HTTP server pro OAuth redirect

/// Minimální HTTP server na 127.0.0.1 s náhodným portem. Přijme jediný redirect
/// z prohlížeče (`/?code=…&state=…`), odpoví krátkou stránkou a skončí.
final class OAuthLoopbackServer: @unchecked Sendable {
    let port: UInt16
    private let socketFD: Int32
    private let lock = NSLock()
    private var cancelled = false
    private var closed = false

    init() throws {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw GoogleCalendarError.message("Nepodařilo se otevřít místní port pro přihlášení.")
        }
        var yes: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bindResult = withUnsafePointer(to: &addr) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, Darwin.listen(fd, 8) == 0 else {
            Darwin.close(fd)
            throw GoogleCalendarError.message("Nepodařilo se otevřít místní port pro přihlášení.")
        }

        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.getsockname(fd, sa, &length)
            }
        }
        guard nameResult == 0 else {
            Darwin.close(fd)
            throw GoogleCalendarError.message("Nepodařilo se zjistit místní port pro přihlášení.")
        }
        socketFD = fd
        port = UInt16(bigEndian: bound.sin_port)
    }

    deinit {
        closeSocket()
    }

    /// Čeká na redirect z prohlížeče a vrátí jeho query parametry (`code`, `state`, případně `error`).
    func waitForCallback(timeout: TimeInterval) async throws -> [String: String] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: String], Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: self.acceptLoop(timeout: timeout))
            }
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    private func closeSocket() {
        lock.lock()
        defer { lock.unlock() }
        if !closed {
            closed = true
            Darwin.close(socketFD)
        }
    }

    private func acceptLoop(timeout: TimeInterval) -> Result<[String: String], Error> {
        defer { closeSocket() }
        let deadline = Date().addingTimeInterval(timeout)
        while !isCancelled && Date() < deadline {
            var pfd = pollfd(fd: socketFD, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&pfd, 1, 250)
            if ready <= 0 { continue }

            let client = Darwin.accept(socketFD, nil, nil)
            if client < 0 { continue }
            var one: Int32 = 1
            _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            var readTimeout = timeval(tv_sec: 2, tv_usec: 0)
            _ = setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &readTimeout, socklen_t(MemoryLayout<timeval>.size))

            if let params = readQuery(from: client), params["code"] != nil || params["error"] != nil {
                let success = params["code"] != nil
                respond(client, status: "200 OK", html: success ? Self.successHTML : Self.failureHTML)
                Darwin.close(client)
                return .success(params)
            }
            // Např. /favicon.ico nebo prázdné předběžné spojení prohlížeče.
            respond(client, status: "404 Not Found", html: "")
            Darwin.close(client)
        }
        if isCancelled { return .failure(CancellationError()) }
        return .failure(GoogleCalendarError.message("Na přihlášení v prohlížeči se čekalo příliš dlouho. Zkus to znovu."))
    }

    private func readQuery(from client: Int32) -> [String: String]? {
        var received: [UInt8] = []
        let capacity = 4096
        var buffer = [UInt8](repeating: 0, count: capacity)
        while received.count < 65536 {
            let count = Darwin.read(client, &buffer, capacity)
            if count <= 0 { break }
            received.append(contentsOf: buffer[0..<count])
            if received.contains(10) { break } // první řádek požadavku je kompletní
        }
        // Stačí první řádek („GET /?code=…&state=… HTTP/1.1“), je čistě ASCII.
        let lineEnd = received.firstIndex(of: 10) ?? received.endIndex
        let firstLine = String(decoding: received[..<lineEnd], as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }
        // Ruční rozbor query – URLComponents(string:) vrací nil u znaků, které prohlížeč nechá nezakódované.
        let target = String(parts[1])
        guard let questionMark = target.firstIndex(of: "?") else { return [:] }
        var result: [String: String] = [:]
        for pair in target[target.index(after: questionMark)...].split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawName = kv.first else { continue }
            func decode(_ s: Substring) -> String {
                let spaced = s.replacingOccurrences(of: "+", with: " ")
                return spaced.removingPercentEncoding ?? spaced
            }
            result[decode(rawName)] = kv.count > 1 ? decode(kv[1]) : ""
        }
        return result
    }

    private func respond(_ client: Int32, status: String, html: String) {
        let body = Array(html.utf8)
        let header = "HTTP/1.1 \(status)\r\n"
            + "Content-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(body.count)\r\n"
            + "Connection: close\r\n\r\n"
        let bytes = Array(header.utf8) + body
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                let written = Darwin.write(client, base.advanced(by: offset), raw.count - offset)
                if written <= 0 { break }
                offset += written
            }
        }
    }

    private static let successHTML = page(
        title: "Hotovo",
        message: "Hotovo, můžeš zavřít okno.",
        detail: "NotchMax je připojený k tvému Google Kalendáři."
    )

    private static let failureHTML = page(
        title: "Přihlášení se nepovedlo",
        message: "Přihlášení se nepovedlo.",
        detail: "Vrať se do NotchMax a zkus to znovu."
    )

    private static func page(title: String, message: String, detail: String) -> String {
        """
        <!doctype html>
        <html lang="cs"><head><meta charset="utf-8"><title>NotchMax – \(title)</title>
        <style>
        body{margin:0;height:100vh;display:flex;align-items:center;justify-content:center;
        background:#111;color:#fff;font-family:-apple-system,BlinkMacSystemFont,sans-serif}
        .card{text-align:center;padding:40px 48px;border-radius:20px;background:#1c1c1e}
        h1{font-size:22px;margin:0 0 8px}p{margin:0;color:#aaa;font-size:14px}
        </style></head>
        <body><div class="card"><h1>\(message)</h1><p>\(detail)</p></div></body></html>
        """
    }
}
