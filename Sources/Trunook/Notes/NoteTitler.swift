import TrunookXPC
import Foundation

/// Имя заметке.
///
/// Имя ставится дважды. Сразу при сохранении — своё, из даты и первой
/// строки: панель обязана закрыться тут же, а не ждать модель. Потом,
/// если модель включена, приходит её вариант, и заметка переименовывается
/// на месте.
///
/// Порядок именно такой, а не «подождём и запишем один раз»: локальная
/// модель думает секунды, а быстрая заметка на то и быстрая. Ждущая панель
/// превратила бы её в обычную.
final class NoteTitler {
    /// Заметка переименована. Зовётся на главном потоке.
    var onTitle: ((Int64, String) -> Void)?

    private let client: OllamaClient
    private let settings: Settings

    /// Очередь ожидающих. Запросы идут по одному: локальная модель
    /// на два разом всё равно отвечает по очереди, а параллельные заставляют
    /// её пересчитывать контекст между ними.
    private var pending: [(id: Int64, plain: String)] = []
    private var isBusy = false

    init(client: OllamaClient = OllamaClient(), settings: Settings = .shared) {
        self.client = client
        self.settings = settings
    }

    var isAvailable: Bool { settings.ollamaEnabled && settings.notesTitleByModel }

    // MARK: - Запасное имя

    /// Наибольшая длина имени. Дальше строка списка всё равно обрезается,
    /// а обрезанная посередине она читается хуже, чем сокращённая по слову.
    static let maxLength = 60
    /// Сколько текста берётся в запасное имя после даты.
    private static let previewLength = 40

    /// Имя без всякой модели: дата и начало текста.
    ///
    /// Дата стоит первой намеренно. Заметок за день бывает несколько, они
    /// начинаются похоже, и список из пяти «Купить…» подряд не разобрать.
    /// Дата же различает их всегда.
    static func fallback(
        for plain: String,
        at date: Date,
        locale: Locale = Localization.shared.resolved.locale
    ) -> String {
        let stamp = stampFormatter(locale: locale).string(from: date)
        let preview = firstLine(of: plain)
        guard !preview.isEmpty else { return stamp }
        return stamp + " — " + truncated(preview, to: previewLength)
    }

    /// Форматтер собирается на каждый вызов, а не хранится: язык интерфейса
    /// меняется на ходу, и хранимый показывал бы месяц на прежнем языке
    /// до перезапуска.
    private static func stampFormatter(locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        // Шаблон, а не жёсткий формат: порядок дня и месяца в разных языках
        // свой, и `setLocalizedDateFormatFromTemplate` расставляет его сам.
        formatter.setLocalizedDateFormatFromTemplate("d MMMM HH:mm")
        return formatter
    }

    private static func firstLine(of text: String) -> String {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty { return Note.oneLine(from: trimmed) }
        }
        return ""
    }

    /// Обрезка по слову, а не по букве: «Купить билеты до пят…» читается,
    /// «Купить билеты до пятн» — нет.
    static func truncated(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        let cut = text.prefix(limit)
        guard let space = cut.lastIndex(of: " "),
              cut.distance(from: cut.startIndex, to: space) > limit / 2
        else { return cut.trimmingCharacters(in: .whitespaces) + "…" }
        return cut[..<space].trimmingCharacters(in: .whitespaces) + "…"
    }

    // MARK: - Имя от модели

    /// Ставит заметку в очередь на именование.
    func enqueue(id: Int64, plain: String) {
        guard isAvailable, !plain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        pending.append((id, plain))
        runNext()
    }

    func cancelAll() {
        pending.removeAll()
    }

    private func runNext() {
        guard !isBusy, !pending.isEmpty else { return }
        let request = pending.removeFirst()
        isBusy = true

        client.generate(prompt: Self.prompt(for: request.plain)) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isBusy = false
                switch result {
                case let .success(answer):
                    if let title = Self.clean(answer) {
                        DebugLog.write("заметки: имя от модели — \(title)")
                        self.onTitle?(request.id, title)
                    } else {
                        DebugLog.write("заметки: модель вернула имя, из которого ничего не вышло")
                    }
                case let .failure(error):
                    DebugLog.write("заметки: имя не придумалось — \(error.localizedDescription)")
                }
                self.runNext()
            }
        }
    }

    /// Промт держим коротким и требовательным: длинные объяснения маленькая
    /// модель понимает хуже, а не лучше, — она начинает отвечать на них.
    static func prompt(for plain: String) -> String {
        let body = truncated(plain, to: 2_000)
        return """
            Придумай короткое название для заметки: не больше шести слов, \
            на языке самой заметки. Ответь одним названием — без кавычек, \
            без пояснений, без точки в конце.

            Заметка:
            \(body)
            """
    }

    // MARK: - Чистка ответа

    /// Слова, с которых модель начинает вместо самого названия.
    private static let leadIns = [
        "название", "заголовок", "вот", "имя",
        "title", "name", "heading",
        "标题", "名称",
    ]

    /// Кавычки всех сортов и знаки разметки, которыми модель обрамляет ответ.
    private static let quotes = CharacterSet(charactersIn: "\"'«»„“”‘’`*#")

    /// Приводит ответ модели к тому, что можно показать в списке.
    ///
    /// Отдельной функцией под тестом, а не `trimmingCharacters` по месту:
    /// модель отвечает то фразой, то кавычками, то абзацем с пояснением,
    /// и каждый из этих случаев ловится своим правилом. По месту их
    /// не собрать и не проверить.
    ///
    /// Возвращает `nil`, когда чистить оказалось нечего: тогда остаётся
    /// прежнее имя, а не пустая строка.
    static func clean(_ raw: String) -> String? {
        var line = firstLine(of: raw)
        guard !line.isEmpty else { return nil }

        line = stripLeadIn(line)
        line = line.trimmingCharacters(in: quotes.union(.whitespaces))
        line = line.trimmingCharacters(in: CharacterSet(charactersIn: ".!…;:"))
        line = line.trimmingCharacters(in: quotes.union(.whitespaces))
        line = Note.oneLine(from: line)

        guard !line.isEmpty else { return nil }
        return truncated(line, to: maxLength)
    }

    /// Срезает «Название: …» и подобное.
    ///
    /// Только по известным словам. Двоеточие само по себе признаком служить
    /// не может: «Отпуск: что взять» — законное название, и резать его
    /// значило бы терять половину.
    private static func stripLeadIn(_ line: String) -> String {
        guard let colon = line.firstIndex(of: ":") else { return line }
        let head = line[..<colon]
            .trimmingCharacters(in: quotes.union(.whitespaces))
            .folded
        guard head.count <= 30, leadIns.contains(where: { head.hasPrefix($0) }) else { return line }
        let tail = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        // Если после двоеточия пусто, значит резать было нечего и вся строка
        // и есть название.
        return tail.isEmpty ? line : tail
    }
}
