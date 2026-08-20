import TrunookXPC
import AppKit
import CoreLocation
import Foundation

/// Погода: где мы находимся, что за окном и что изменится в ближайшие часы.
///
/// Источник — Open-Meteo: он не требует ни ключа, ни регистрации. WeatherKit
/// от Apple подошёл бы лучше, но он привязан к платной учётной записи
/// разработчика, а приложение подписано самодельным сертификатом.
///
/// Это единственное место, откуда что-то уходит в интернет: наружу отправляются
/// округлённые до сотой доли градуса координаты — это примерно километр,
/// и погоде большей точности не нужно.
final class WeatherService: NSObject, ObservableObject {
    struct Outlook: Equatable {
        let condition: WeatherCondition
        /// Через сколько часов начнётся.
        let inHours: Int
        let probability: Int
    }

    struct Snapshot: Equatable {
        let temperature: Int
        let condition: WeatherCondition
        let updatedAt: Date
        /// Ближайшие осадки, если они ожидаются в окне прогноза.
        let outlook: Outlook?
    }

    @Published private(set) var current: Snapshot?
    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var error: String?

    /// Текст и значок для плашки в вырезе.
    var onAlert: ((_ text: String, _ symbol: String) -> Void)?

    private let settings: Settings
    private let manager = CLLocationManager()
    private let session: URLSession

    private var refreshTimer: Timer?
    private var location: CLLocation?
    /// На что мы уже реагировали: без этой памяти плашка о дожде всплывала бы
    /// каждые четверть часа, пока дождь остаётся в прогнозе.
    private var announcedCondition: WeatherCondition?
    private var announcedOutlook: WeatherCondition?
    private var lastPeriodicAlert = Date.distantPast

    /// Как часто спрашиваем сервис. Прогноз обновляется раз в час, чаще
    /// незачем — и вежливее к бесплатному источнику.
    private static let refreshInterval: TimeInterval = 15 * 60
    /// Насколько вперёд смотрим в поисках осадков.
    private static let outlookHours = 6

    init(settings: Settings = .shared) {
        self.settings = settings
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        authorization = manager.authorizationStatus
    }

    // MARK: - Жизненный цикл

    func start() {
        guard settings.weatherEnabled else { return }
        // Доступ спрашивается только когда координаты и правда нужны:
        // с выбранным городом система про положение не спрашивается вовсе,
        // и диалога человек не видит.
        if settings.weatherSource == .location { requestAccessIfNeeded() }

        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        refresh()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    /// Настройку включили на ходу — начинаем, не дожидаясь перезапуска.
    func restart() {
        stop()
        current = nil
        announcedCondition = nil
        announcedOutlook = nil
        start()
    }

    /// После отказа система больше не спросит — остаётся путь через
    /// Системные настройки.
    static func openPrivacySettings() {
        let address = "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }

    func requestAccessIfNeeded() {
        guard authorization == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    func refresh() {
        guard settings.weatherEnabled else { return }

        // Выбранный город — прямой путь: координаты уже известны, спрашивать
        // их не у кого и незачем.
        //
        // Возврат безусловный, даже когда город ещё не назван: человек выбрал
        // «по городу», и подменять его выбор геопозицией нельзя — иначе
        // приложение спрашивало бы у системы положение ровно там, где обещало
        // этого не делать.
        if settings.weatherSource == .place {
            guard let place = settings.weatherPlace else { return }
            load(latitude: place.latitude, longitude: place.longitude)
            return
        }

        guard authorization == .authorized || authorization == .authorizedAlways else {
            return
        }
        // Одна засечка положения на обновление: держать поток координат ради
        // погоды — расточительно для батареи.
        manager.requestLocation()
    }

    /// Место сменили в настройках — перечитываем прогноз, не дожидаясь
    /// четвертьчасового тика: иначе выбранный город появился бы через
    /// пятнадцать минут, и выглядело бы это как «не сработало».
    func placeChanged() {
        current = nil
        announcedCondition = nil
        announcedOutlook = nil
        if settings.weatherSource == .location { requestAccessIfNeeded() }
        refresh()
    }

    // MARK: - Запрос прогноза

    private func load(for location: CLLocation) {
        load(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    private func load(latitude rawLatitude: Double, longitude rawLongitude: Double) {
        // Округление до сотой доли градуса — это примерно километр, и погоде
        // точнее не нужно. Для выбранного города оно и подавно безобидно,
        // но путь пусть будет один: меньше поводов однажды отправить лишнее.
        let latitude = (rawLatitude * 100).rounded() / 100
        let longitude = (rawLongitude * 100).rounded() / 100

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "hourly", value: "weather_code,precipitation_probability"),
            URLQueryItem(name: "forecast_hours", value: String(Self.outlookHours)),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = components?.url else { return }

        session.dataTask(with: url) { [weak self] data, _, failure in
            guard let self else { return }
            if let failure {
                DispatchQueue.main.async { self.error = failure.localizedDescription }
                DebugLog.write("погода: \(failure.localizedDescription)")
                return
            }
            guard let data, let snapshot = Self.parse(data) else {
                DebugLog.write("погода: ответ не разобран")
                return
            }
            DispatchQueue.main.async { self.apply(snapshot) }
        }.resume()
    }

    private static func parse(_ data: Data) -> Snapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let currentBlock = root["current"] as? [String: Any],
              let temperature = currentBlock["temperature_2m"] as? Double,
              let code = currentBlock["weather_code"] as? Int
        else { return nil }

        var outlook: Outlook?
        if let hourly = root["hourly"] as? [String: Any],
           let codes = hourly["weather_code"] as? [Int] {
            let chances = hourly["precipitation_probability"] as? [Int] ?? []
            // Первый элемент — текущий час, его пропускаем: это уже «сейчас».
            for index in 1..<codes.count {
                let condition = WeatherCondition(wmo: codes[index])
                guard condition.isPrecipitation else { continue }
                outlook = Outlook(
                    condition: condition,
                    inHours: index,
                    probability: index < chances.count ? chances[index] : 0
                )
                break
            }
        }

        return Snapshot(
            temperature: Int(temperature.rounded()),
            condition: WeatherCondition(wmo: code),
            updatedAt: Date(),
            outlook: outlook
        )
    }

    // MARK: - Когда предупреждать

    private func apply(_ snapshot: Snapshot) {
        error = nil
        let previous = current
        current = snapshot
        DebugLog.write("погода: \(snapshot.condition.rawValue), \(snapshot.temperature)°"
                       + (snapshot.outlook.map { ", через \($0.inHours) ч \($0.condition.rawValue)" } ?? ""))

        switch settings.weatherAlertMode {
        case .periodic:
            let period = TimeInterval(settings.weatherPeriodHours) * 3600
            guard Date().timeIntervalSince(lastPeriodicAlert) >= period else { return }
            lastPeriodicAlert = Date()
            announce(text: "\(snapshot.condition.title), \(formatted(snapshot.temperature))",
                     symbol: snapshot.condition.symbol)

        case .onChange:
            // Скорые осадки важнее смены облачности: о них и предупреждаем,
            // причём один раз на явление, а не каждые пятнадцать минут.
            if let outlook = snapshot.outlook, outlook.condition != announcedOutlook {
                announcedOutlook = outlook.condition
                announcedCondition = snapshot.condition
                announce(
                    text: tf("Через %d ч %@", outlook.inHours, outlook.condition.title.lowercased()),
                    symbol: outlook.condition.symbol
                )
                return
            }
            if snapshot.outlook == nil { announcedOutlook = nil }

            let known = announcedCondition ?? previous?.condition
            guard let known, known != snapshot.condition else {
                announcedCondition = snapshot.condition
                return
            }
            announcedCondition = snapshot.condition
            announce(text: "\(snapshot.condition.title), \(formatted(snapshot.temperature))",
                     symbol: snapshot.condition.symbol)
        }
    }

    private func announce(text: String, symbol: String) {
        DebugLog.write("погода: плашка «\(text)»")
        onAlert?(text, symbol)
    }

    /// Градусы Цельсия со знаком: минус читается сразу, плюс не мешает.
    func formatted(_ temperature: Int) -> String {
        "\(temperature)°"
    }
}

extension WeatherService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        DebugLog.write("погода: доступ к геопозиции — \(authorization.rawValue)")
        // Только когда положение и правда нужно: с выбранным городом
        // ответ системы про разрешение нас не касается, а перечитывать
        // по нему прогноз — лишний запрос на пустом месте.
        guard settings.weatherSource == .location else { return }
        if authorization == .authorized || authorization == .authorizedAlways {
            refresh()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        location = last
        load(for: last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DebugLog.write("погода: положение не определилось — \(error.localizedDescription)")
        // Последнее известное всё ещё годится: погода не меняется от того,
        // что система сейчас не смогла уточнить координаты.
        if let location { load(for: location) }
    }
}
