import TrunookXPC
import Foundation

/// Прогноз на неделю для Trudaybook: по дням и по часам, с прошлой недели
/// по следующую, — файлом `~/Library/Application Support/Trunook/weather-week.json`.
///
/// Тот же Open-Meteo и те же округлённые координаты, что у погоды выреза:
/// нового адресата у данных нет. Раз в час — прогноз на дни вперёд чаще
/// не меняется, а источник бесплатный.
final class WeekForecastExport {
    static let refreshInterval: TimeInterval = 3600

    private let settings: Settings
    private let session: URLSession
    private let file: URL
    private var lastFetch = Date.distantPast
    private var lastCoordinates: (Double, Double)?

    init(settings: Settings = .shared, file: URL? = nil) {
        self.settings = settings
        self.file = file ?? Self.defaultFile
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
    }

    static var defaultFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Trunook/weather-week.json")
    }

    /// Погода выреза узнала координаты. Запрос — если сменилось место,
    /// прошёл час или файла нет.
    func coordinatesChanged(latitude: Double, longitude: Double) {
        let moved = lastCoordinates.map { $0.0 != latitude || $0.1 != longitude } ?? true
        let due = Date().timeIntervalSince(lastFetch) >= Self.refreshInterval
        guard moved || due || !FileManager.default.fileExists(atPath: file.path) else { return }
        lastCoordinates = (latitude, longitude)
        lastFetch = Date()
        fetch(latitude: latitude, longitude: longitude)
    }

    private func fetch(latitude: Double, longitude: Double) {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,precipitation_probability"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "past_days", value: "7"),
            URLQueryItem(name: "forecast_days", value: "8"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = components?.url else { return }
        let place = settings.weatherSource == .location ? nil : settings.weatherPlace?.name
        session.dataTask(with: url) { [weak self] data, _, failure in
            guard let self else { return }
            guard failure == nil, let data, let export = Self.export(from: data, now: Date(), place: place) else {
                DebugLog.write("прогноз недели: не получен — \(failure?.localizedDescription ?? "ответ не разобран")")
                return
            }
            do {
                try FileManager.default.createDirectory(at: self.file.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try export.write(to: self.file, options: .atomic)
                DebugLog.write("прогноз недели: записан для Trudaybook")
            } catch {
                DebugLog.write("прогноз недели: не записан — \(error.localizedDescription)")
            }
        }.resume()
    }

    /// Ответ Open-Meteo — в файл для Trudaybook. Часы у Open-Meteo местные
    /// и без пояса («2026-09-25T09:00»), смещение приходит отдельно
    /// (`utc_offset_seconds`); в файл они идут абсолютным временем.
    static func export(from data: Data, now: Date, place: String?) -> Data? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let hourly = root["hourly"] as? [String: Any],
              let daily = root["daily"] as? [String: Any],
              let hourTimes = hourly["time"] as? [String],
              let dayTimes = daily["time"] as? [String] else { return nil }
        let offset = (root["utc_offset_seconds"] as? NSNumber)?.doubleValue ?? 0
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = TimeZone(secondsFromGMT: 0)
        local.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let iso = ISO8601DateFormatter()

        func numbers(_ block: [String: Any], _ key: String) -> [Double?] {
            ((block[key] as? [Any]) ?? []).map { ($0 as? NSNumber)?.doubleValue }
        }
        let temperatures = numbers(hourly, "temperature_2m")
        let codes = numbers(hourly, "weather_code")
        let chances = numbers(hourly, "precipitation_probability")
        var hours: [[String: Any]] = []
        for (index, raw) in hourTimes.enumerated() {
            guard let time = local.date(from: raw),
                  index < temperatures.count, let temperature = temperatures[index],
                  index < codes.count, let code = codes[index] else { continue }
            hours.append([
                "time": iso.string(from: time.addingTimeInterval(-offset)),
                "temp": (temperature * 10).rounded() / 10,
                "code": Int(code),
                "precip": Int((index < chances.count ? chances[index] : nil) ?? 0),
            ])
        }
        let dayCodes = numbers(daily, "weather_code")
        let maxima = numbers(daily, "temperature_2m_max")
        let minima = numbers(daily, "temperature_2m_min")
        let dayChances = numbers(daily, "precipitation_probability_max")
        var days: [[String: Any]] = []
        for (index, date) in dayTimes.enumerated() {
            guard index < dayCodes.count, let code = dayCodes[index],
                  index < maxima.count, let max = maxima[index],
                  index < minima.count, let min = minima[index] else { continue }
            days.append(["date": date, "code": Int(code), "max": max, "min": min,
                         "precip": Int((index < dayChances.count ? dayChances[index] : nil) ?? 0)])
        }
        guard !days.isEmpty || !hours.isEmpty else { return nil }
        var json: [String: Any] = ["version": 1, "updated": iso.string(from: now), "days": days, "hours": hours]
        if let place { json["place"] = place }
        return try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
    }
}
