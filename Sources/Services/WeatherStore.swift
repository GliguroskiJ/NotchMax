import Foundation
import SwiftUI

// MARK: - Modely

struct WeatherCurrent: Equatable {
    var temperature: Double
    var apparent: Double
    var code: Int
    var windKmh: Double
    var isDay: Bool
}

struct WeatherDay: Identifiable, Equatable {
    /// ISO datum "yyyy-MM-dd".
    let date: String
    let code: Int
    let min: Double
    let max: Double

    var id: String { date }

    /// Česká zkratka dne v týdnu (z ISO data, bez závislosti na časovém pásmu).
    var weekdayShort: String {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return "" }
        var cal = Calendar(identifier: .gregorian)
        if let utc = TimeZone(identifier: "UTC") { cal.timeZone = utc }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        comps.hour = 12
        guard let d = cal.date(from: comps) else { return "" }
        let names = ["Ne", "Po", "Út", "St", "Čt", "Pá", "So"]
        let index = cal.component(.weekday, from: d) - 1
        guard index >= 0 && index < names.count else { return "" }
        return names[index]
    }
}

enum WeatherLoadState: Equatable {
    case idle
    case loading
    case loaded
    case error(String)
}

// MARK: - Mapování WMO kódů

enum WeatherCodes {
    /// WMO weather_code -> (SF Symbol, český popis).
    static func info(code: Int, isDay: Bool) -> (symbol: String, text: String) {
        switch code {
        case 0:
            return (isDay ? "sun.max.fill" : "moon.stars.fill", "Jasno")
        case 1:
            return (isDay ? "cloud.sun.fill" : "cloud.moon.fill", "Převážně jasno")
        case 2:
            return (isDay ? "cloud.sun.fill" : "cloud.moon.fill", "Polojasno")
        case 3:
            return ("cloud.fill", "Zataženo")
        case 45, 48:
            return ("cloud.fog.fill", "Mlha")
        case 51, 53, 55:
            return ("cloud.drizzle.fill", "Mrholení")
        case 56, 57:
            return ("cloud.drizzle.fill", "Mrznoucí mrholení")
        case 61:
            return ("cloud.rain.fill", "Slabý déšť")
        case 63:
            return ("cloud.rain.fill", "Déšť")
        case 65:
            return ("cloud.heavyrain.fill", "Silný déšť")
        case 66, 67:
            return ("cloud.rain.fill", "Mrznoucí déšť")
        case 71, 73, 75, 77:
            return ("cloud.snow.fill", "Sněžení")
        case 80, 81, 82:
            return (isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill", "Přeháňky")
        case 85, 86:
            return ("cloud.snow.fill", "Sněhové přeháňky")
        case 95, 96, 99:
            return ("cloud.bolt.rain.fill", "Bouřka")
        default:
            return ("cloud.fill", "Neznámé počasí")
        }
    }
}

// MARK: - Dekódování odpovědí Open-Meteo

private struct GeoResponse: Decodable {
    let results: [GeoResult]?
}

private struct GeoResult: Decodable {
    let name: String
    let latitude: Double
    let longitude: Double
}

private struct ForecastResponse: Decodable {
    struct Current: Decodable {
        let temperature2m: Double
        let apparentTemperature: Double
        let weatherCode: Int
        let windSpeed10m: Double
        let isDay: Int

        enum CodingKeys: String, CodingKey {
            case temperature2m = "temperature_2m"
            case apparentTemperature = "apparent_temperature"
            case weatherCode = "weather_code"
            case windSpeed10m = "wind_speed_10m"
            case isDay = "is_day"
        }
    }

    struct Daily: Decodable {
        let time: [String]
        let weatherCode: [Int]
        let temperatureMax: [Double]
        let temperatureMin: [Double]

        enum CodingKeys: String, CodingKey {
            case time
            case weatherCode = "weather_code"
            case temperatureMax = "temperature_2m_max"
            case temperatureMin = "temperature_2m_min"
        }
    }

    let current: Current
    let daily: Daily
}

private enum WeatherError: Error {
    case notFound
    case badResponse
}

// MARK: - Store

@MainActor
final class WeatherStore: ObservableObject {
    static let shared = WeatherStore()

    private static let cityKey = "weatherCity"
    private static let defaultCity = "Praha"
    private static let maxAge: TimeInterval = 30 * 60

    @Published private(set) var city: String
    @Published private(set) var cityName: String
    @Published private(set) var current: WeatherCurrent?
    @Published private(set) var daily: [WeatherDay] = []
    @Published private(set) var state: WeatherLoadState = .idle
    @Published private(set) var lastUpdate: Date?

    /// Město, pro které jsou aktuálně načtená data.
    private var loadedCity: String?
    private var requestID = 0
    private var loadTask: Task<Void, Never>?

    private init() {
        let saved = UserDefaults.standard.string(forKey: WeatherStore.cityKey) ?? ""
        let trimmed = saved.trimmingCharacters(in: .whitespacesAndNewlines)
        let initial = trimmed.isEmpty ? WeatherStore.defaultCity : trimmed
        city = initial
        cityName = initial
    }

    // MARK: Veřejné API

    /// Načte data jen když jsou starší než 30 minut, nebo se změnilo město.
    func refreshIfNeeded() async {
        if state == .loading, let task = loadTask {
            await task.value
            return
        }
        if state == .loaded, loadedCity == city, let last = lastUpdate,
           Date().timeIntervalSince(last) < WeatherStore.maxAge {
            return
        }
        await refresh()
    }

    /// Vynucené obnovení (tlačítko „Zkusit znovu“).
    func refresh() async {
        let task = startLoad()
        await task.value
    }

    func setCity(_ newCity: String) {
        let trimmed = newCity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UserDefaults.standard.set(trimmed, forKey: WeatherStore.cityKey)
        city = trimmed
        _ = startLoad()
    }

    // MARK: Načítání

    private func startLoad() -> Task<Void, Never> {
        requestID += 1
        let id = requestID
        loadTask?.cancel()
        let task: Task<Void, Never> = Task { [weak self] in
            await self?.perform(id: id)
        }
        loadTask = task
        return task
    }

    private func perform(id: Int) async {
        let requestedCity = city
        if loadedCity != requestedCity {
            current = nil
            daily = []
            cityName = requestedCity
        }
        state = .loading

        do {
            let place = try await geocode(requestedCity)
            let forecast = try await fetchForecast(latitude: place.latitude, longitude: place.longitude)
            guard id == requestID else { return }

            current = WeatherCurrent(
                temperature: forecast.current.temperature2m,
                apparent: forecast.current.apparentTemperature,
                code: forecast.current.weatherCode,
                windKmh: forecast.current.windSpeed10m,
                isDay: forecast.current.isDay != 0
            )

            let d = forecast.daily
            let count = min(d.time.count, d.weatherCode.count, d.temperatureMax.count, d.temperatureMin.count)
            var days: [WeatherDay] = []
            for i in 0..<count {
                days.append(WeatherDay(date: d.time[i], code: d.weatherCode[i],
                                       min: d.temperatureMin[i], max: d.temperatureMax[i]))
            }
            daily = days
            cityName = place.name
            loadedCity = requestedCity
            lastUpdate = Date()
            state = .loaded
        } catch {
            guard id == requestID else { return }
            if error is CancellationError {
                state = .idle
                return
            }
            if let weatherError = error as? WeatherError, weatherError == .notFound {
                state = .error("Město „\(requestedCity)“ nebylo nalezeno.")
            } else if error is URLError {
                state = .error("Nelze se připojit k serveru počasí.")
            } else {
                state = .error("Počasí se nepodařilo načíst.")
            }
        }
    }

    private func request(_ components: URLComponents) throws -> URLRequest {
        guard let url = components.url else { throw WeatherError.badResponse }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        return req
    }

    private func geocode(_ name: String) async throws -> GeoResult {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "cs")
        ]
        guard let comps = components else { throw WeatherError.badResponse }
        let (data, response) = try await URLSession.shared.data(for: request(comps))
        try WeatherStore.checkStatus(response)
        let decoded = try JSONDecoder().decode(GeoResponse.self, from: data)
        guard let first = decoded.results?.first else { throw WeatherError.notFound }
        return first
    }

    private func fetchForecast(latitude: Double, longitude: Double) async throws -> ForecastResponse {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,wind_speed_10m,is_day"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "5")
        ]
        guard let comps = components else { throw WeatherError.badResponse }
        let (data, response) = try await URLSession.shared.data(for: request(comps))
        try WeatherStore.checkStatus(response)
        return try JSONDecoder().decode(ForecastResponse.self, from: data)
    }

    private static func checkStatus(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WeatherError.badResponse
        }
    }
}
