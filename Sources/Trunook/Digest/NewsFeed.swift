import Foundation

/// Поиск новостей: лента Google News по запросу.
///
/// Без ключа и без учётной записи, отдаёт заголовок, источник, время
/// и ссылку — ровно то, что нужно сводке. Текст статей не берётся: ссылки
/// ведут через переадресацию Google, которую без браузера не пройти,
/// а отбирать и пересказывать по заголовкам модели хватает.
enum NewsFeed {
    /// Издание ленты — язык и страна.
    struct Edition: Equatable {
        let language: String
        let country: String
        let ceid: String
    }

    static let russian = Edition(language: "ru", country: "RU", ceid: "RU:ru")
    static let english = Edition(language: "en-US", country: "US", ceid: "US:en")
    static let chinese = Edition(language: "zh-CN", country: "CN", ceid: "CN:zh-Hans")

    /// Издание по языку самого запроса, а без явных букв — по языку
    /// интерфейса.
    ///
    /// По запросу, а не по интерфейсу, потому что «ставка ЦБ» в английской
    /// ленте не найдёт ничего, даже если приложение по-английски. Запрос
    /// латиницей («OpenAI») языка не выдаёт — тогда решает интерфейс.
    static func edition(for query: String, interface: Language) -> Edition {
        for scalar in query.unicodeScalars {
            switch scalar.value {
            case 0x0400...0x04FF: return russian
            case 0x4E00...0x9FFF: return chinese
            default: continue
            }
        }
        switch interface {
        case .ru: return russian
        case .zh: return chinese
        case .en, .system: return english
        }
    }

    /// Адрес поиска. `when:` сужает выдачу на стороне Google; точная граница
    /// по времени всё равно проводится у нас, в `NewsCandidates`.
    static func url(query: String, since: Date, now: Date, edition: Edition) -> URL? {
        let days = max(1, Int((now.timeIntervalSince(since) / 86_400).rounded(.up)))
        var components = URLComponents(string: "https://news.google.com/rss/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: "\(query) when:\(days)d"),
            URLQueryItem(name: "hl", value: edition.language),
            URLQueryItem(name: "gl", value: edition.country),
            URLQueryItem(name: "ceid", value: edition.ceid),
        ]
        return components?.url
    }
}

/// Разбор RSS в список новостей.
final class NewsFeedParser: NSObject, XMLParserDelegate {
    static func parse(_ data: Data) -> [NewsItem] {
        let delegate = NewsFeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.items
    }

    /// Дата RSS: «Sat, 12 Sep 2026 23:52:15 GMT». Локаль постоянная — иначе
    /// на русской системе «Sat» не разберётся.
    static func date(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Заголовок в ленте Google оканчивается источником: «Новость - bbc.com».
    /// Хвост снимается, только если он и правда совпадает с источником, —
    /// дефис бывает и частью самого заголовка.
    ///
    /// Снимается, пока совпадает: у части изданий Google приписывает источник
    /// дважды — «Новость - NEWSru.co.il - NEWSru.co.il», — и после одного
    /// снятия хвост оставался в сводке.
    static func cleanTitle(_ title: String, source: String) -> String {
        var trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = " - " + source
        guard !source.isEmpty else { return trimmed }
        while trimmed.hasSuffix(suffix), trimmed.count > suffix.count {
            trimmed = String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

    private var items: [NewsItem] = []
    private var inItem = false
    private var element = ""
    private var title = ""
    private var link = ""
    private var published = ""
    private var source = ""

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        element = name
        if name == "item" {
            inItem = true
            title = ""; link = ""; published = ""; source = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inItem else { return }
        switch element {
        case "title": title += string
        case "link": link += string
        case "pubDate": published += string
        case "source": source += string
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        element = ""
        guard name == "item" else { return }
        inItem = false
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              let date = Self.date(published)
        else { return }
        let clean = Self.cleanTitle(title, source: source)
        guard !clean.isEmpty else { return }
        items.append(NewsItem(title: clean, source: source, link: url, published: date))
    }
}

/// Что показать модели: свежее, без повторов и не слишком много.
enum NewsCandidates {
    /// Сорок заголовков — около двух тысяч токенов: помещается в окно
    /// маленькой модели и оставляет ей место подумать над выбором.
    static let limit = 40

    static func prepare(_ items: [NewsItem], since: Date, limit: Int = limit) -> [NewsItem] {
        var seen = Set<String>()
        var result: [NewsItem] = []
        for item in items.sorted(by: { $0.published > $1.published }) where item.published >= since {
            // Одна новость в пяти изданиях приходит пятью строками с почти
            // одинаковым заголовком. Ловим точные повторы — остальное модель
            // склеит сама, её об этом просят.
            let key = normalized(item.title)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(item)
            if result.count == limit { break }
        }
        return result
    }

    static func normalized(_ title: String) -> String {
        String(title.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .prefix(80)
            .map(Character.init))
    }
}
