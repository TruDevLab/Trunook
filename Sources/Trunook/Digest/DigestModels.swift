import Foundation

/// Тема сводки: то, что человек написал, и поисковые запросы по ней.
///
/// Запросы отдельно от названия, потому что «что нового в мире кино» — хорошая
/// тема и плохой поисковый запрос: поиск новостей ищет слова, а не смысл.
/// Переписывает их модель один раз, при первой сборке, и они хранятся
/// рядом. Меняется название — запросы сбрасываются и пишутся заново.
struct DigestTopic: Codable, Equatable, Identifiable {
    var id: Int
    var title: String
    var queries: [String] = []
    var isEnabled: Bool = true

    /// Что уйдёт в поиск: переписанные запросы, а без них — само название.
    var searchQueries: [String] {
        let cleaned = queries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned.isEmpty ? [title] : cleaned
    }
}

enum DigestTopics {
    static let key = "digestTopics"

    static func load(from defaults: UserDefaults) -> [DigestTopic] {
        guard let data = defaults.data(forKey: key),
              let stored = try? JSONDecoder().decode([DigestTopic].self, from: data)
        else { return [] }
        return stored
    }

    static func save(_ topics: [DigestTopic], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(topics) else { return }
        defaults.set(data, forKey: key)
    }

    static func nextID(after topics: [DigestTopic]) -> Int {
        (topics.map(\.id).max() ?? -1) + 1
    }
}

/// Новость из ленты — до того, как её отобрала модель.
struct NewsItem: Equatable {
    var title: String
    var source: String
    var link: URL
    var published: Date
}

/// Готовая сводка.
struct Digest: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var createdAt: Date
    /// С какого времени искались новости.
    var since: Date
    var sections: [DigestSection]

    var entryCount: Int { sections.reduce(0) { $0 + $1.entries.count } }
}

struct DigestSection: Codable, Equatable, Identifiable {
    var id: Int
    var title: String
    var entries: [DigestEntry]
    /// Тему собрать не удалось: сеть или модель. Отдельно от пустой темы —
    /// «новостей не нашлось» и «не получилось поискать» человек должен
    /// различать.
    var failed: Bool = false
}

struct DigestEntry: Codable, Equatable, Identifiable {
    var title: String
    var source: String
    var link: URL
    var published: Date
    /// Одно предложение от модели. Может быть пустым: заголовка тогда хватает.
    var summary: String

    var id: String { link.absoluteString }
}
