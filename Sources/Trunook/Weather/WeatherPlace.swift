import TrunookXPC
import Foundation

/// Откуда берутся координаты для прогноза.
enum WeatherSource: String, CaseIterable, Identifiable {
    /// По геопозиции — точнее и само следует за переездом.
    case location
    /// По названному городу — не требует доступа к геопозиции вовсе.
    case place

    var id: String { rawValue }

    var title: String {
        switch self {
        case .location: return t("По геопозиции")
        case .place: return t("По выбранному городу")
        }
    }
}

/// Город, для которого спрашивается погода.
///
/// Координаты хранятся вместе с названием, а не ищутся заново при каждом
/// запросе: название неоднозначно — Ростовов два, Владимиров тоже, — и повторный
/// поиск однажды выбрал бы другой из них. Выбор человека сохраняется целиком.
struct WeatherPlace: Codable, Equatable, Identifiable {
    let name: String
    /// Область и страна: ими один Ростов отличается от другого. Пусто,
    /// если сервис ничего не сообщил.
    let region: String?
    let latitude: Double
    let longitude: Double

    /// Идентификатор — координаты: сервис своих не гарантирует, а тёзки
    /// в списке результатов различаются именно положением.
    var id: String { "\(latitude),\(longitude)" }

    /// Строка для списка и для настроек: «Ростов, Ярославская область, Россия».
    var title: String {
        guard let region, !region.isEmpty else { return name }
        return "\(name), \(region)"
    }
}

/// Поиск города по названию.
///
/// Тот же Open-Meteo, что и прогноз, и по той же причине: ни ключа,
/// ни регистрации. Наружу уходит только введённое название — то есть ровно
/// то, что человек набрал сам, чтобы не отдавать геопозицию.
final class WeatherPlaceSearch: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [WeatherPlace] = []
    @Published private(set) var isSearching = false
    /// Что показать вместо списка: «ничего не нашлось» или текст ошибки сети.
    @Published private(set) var message: String?

    private let session: URLSession
    private var task: URLSessionDataTask?

    /// Сколько городов показываем. Больше десятка — это уже не выбор из тёзок,
    /// а список всех населённых пунктов с таким корнем.
    private static let limit = 10

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration)
    }

    func search() {
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // Одна буква даёт тысячу городов и ни одного нужного.
        guard name.count >= 2 else {
            reset()
            return
        }

        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "count", value: String(Self.limit)),
            // Язык ответа — язык интерфейса: искать «Мюнхен» и получить
            // «München» человек не ожидает.
            URLQueryItem(name: "language", value: Self.language),
            URLQueryItem(name: "format", value: "json"),
        ]
        guard let url = components?.url else { return }

        // Предыдущий запрос отменяем: набирают быстрее, чем отвечает сеть,
        // и ответ на позавчерашнюю букву перебил бы свежий список.
        task?.cancel()
        isSearching = true
        message = nil

        let task = session.dataTask(with: url) { [weak self] data, _, failure in
            guard let self else { return }
            if let failure {
                // Отмена — не ошибка: её вызвали мы сами, следующим запросом.
                guard (failure as NSError).code != NSURLErrorCancelled else { return }
                DispatchQueue.main.async {
                    self.isSearching = false
                    self.message = failure.localizedDescription
                }
                return
            }
            let found = data.flatMap { Self.parse($0) } ?? []
            DispatchQueue.main.async {
                self.isSearching = false
                self.results = found
                self.message = found.isEmpty ? t("Ничего не нашлось") : nil
            }
        }
        self.task = task
        task.resume()
    }

    func reset() {
        task?.cancel()
        task = nil
        isSearching = false
        results = []
        message = nil
    }

    /// Разбор ответа геокодера.
    ///
    /// Отдельной функцией и без сети внутри: только так его можно проверить
    /// тестом — у ответа много необязательных полей, и путаница в них
    /// показала бы человеку список безымянных городов.
    static func parse(_ data: Data) -> [WeatherPlace] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["results"] as? [[String: Any]]
        else { return [] }

        return list.compactMap { item in
            guard let name = item["name"] as? String,
                  let latitude = item["latitude"] as? Double,
                  let longitude = item["longitude"] as? Double
            else { return nil }
            // admin1 — область или штат, country — страна. Обоих может
            // не быть: у мелких мест сервис их не заполняет.
            let region = [item["admin1"] as? String, item["country"] as? String]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            return WeatherPlace(
                name: name,
                region: region.isEmpty ? nil : region,
                latitude: latitude,
                longitude: longitude
            )
        }
    }

    /// Код языка для геокодера.
    ///
    /// Берётся `resolved`, а не `current`: «как в системе» — это не язык,
    /// и сервис получил бы слово «system». Код свой, а не `folder`: там
    /// «zh-Hans», а геокодер ждёт двухбуквенный.
    private static var language: String {
        switch Localization.shared.resolved {
        case .ru: return "ru"
        case .zh: return "zh"
        case .en, .system: return "en"
        }
    }
}
