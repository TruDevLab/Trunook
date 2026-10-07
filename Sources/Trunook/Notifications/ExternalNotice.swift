import TrunookXPC
import Foundation

/// Уведомление, присланное в вырез снаружи — скриптом, хуком, автоматикой.
///
/// Значение, а не ссылка на файл, из которого оно пришло: файл к этому
/// моменту уже прочитан и убран, а плашка обязана пережить его исчезновение.
///
/// Почему вообще снаружи. Всё, о чём вырез рассказывает, он знает сам:
/// календарь, погода, батарея, буфер. Но самое ценное уведомление — то,
/// которое **ждёт ответа**: сборка спрашивает «выкатывать?», помощник
/// в терминале — «можно записать файл?». Знать о таком изнутри нечем,
/// а спросить через вырез — ровно то, для чего он и сделан.
struct ExternalNotice: Equatable, Identifiable {
    /// Кнопка в плашке. Больше двух не бывает: ширина плашки 360 точек,
    /// и третья кнопка съела бы сам вопрос.
    struct Action: Equatable {
        /// Что уйдёт ответом: «yes», «no», своё слово.
        let id: String
        /// Подпись под чёлкой при наведении: «Принять», «Отклонить».
        let title: String
        let symbol: String
        /// Зелёная ли кнопка. У согласия и отказа разный вес, и одинаковые
        /// кнопки заставляли бы читать подпись каждый раз.
        let isPositive: Bool
        /// Кнопка открывает окно приславшего (`"opens": true`) — ответ,
        /// пересылку: тогда его выводят вперёд. Архив и «напомнить позже»
        /// делаются в фоне, и уводить человека от работы незачем.
        var opensApp = false
    }

    let id: String
    /// Кто прислал — своим словом, а не путём к файлу: «Сборка», «Помощник».
    let source: String
    let title: String
    let symbol: String
    /// Сколько держать плашку. Бесконечность — «пока не ответят».
    let hold: TimeInterval
    let actions: [Action]
    /// Куда написать ответ. Файл, а не сеть: тот, кто прислал вопрос, уже
    /// умеет ждать файла — на этом стоят все хуки и все сборочные скрипты.
    let replyPath: String?
    /// Кнопки — предложение, а не вопрос (`"optional": true`): плашка уходит
    /// сама через `hold`, и никто её не возвращает. Так приходит почта —
    /// «Ответить» и «В архив» под письмом, о котором можно и забыть.
    let isOptional: Bool
    /// Залп конфетти из чёлки вместе с плашкой (`"celebrate": true`) —
    /// так Trudaybook отмечает «всё разобрано». Безвреден: ничего, кроме
    /// картинки, и тот не чаще раза в минуту (`NotchController.present`).
    let celebrates: Bool
    /// О какой встрече плашка (`"event": {"title", "start"}`). По нему
    /// Trunook узнаёт встречу из своего календаря и не показывает её дважды:
    /// Exchange бывает подключён и к macOS, и к Trudaybook напрямую.
    let event: EventRef?
    /// Письмо целиком для превью (`"preview": {"from","subject","text","date"}`).
    /// Решить «в архив» или «ответить» по одной строке под чёлкой нельзя —
    /// письмо надо сперва прочитать. С превью кнопка `"preview"` открывает
    /// его прямо в вырезе, а не уходит ответом.
    let preview: LetterPreview?

    struct EventRef: Equatable {
        let title: String
        let start: Date
    }

    struct LetterPreview: Equatable {
        let from: String
        let subject: String
        let text: String
        /// Как показать дату — строкой отправителя: «сегодня, 14:05».
        let date: String
        /// Быстрые действия под текстом: ответить всем, в архив, переслать,
        /// напомнить позже. Не больше четырёх; ответ — тем же файлом, что
        /// и с кнопок плашки.
        var actions: [Action] = []
        /// Письмо-приглашение: когда встреча и что в этот день рядом с ней
        /// (`"meeting": {"start","end","allDay","location","events":[…]}`).
        var meeting: Meeting?

        static let maxActions = 4

        struct Meeting: Equatable {
            let start: Date
            let end: Date
            let isAllDay: Bool
            let location: String
            /// Встречи того дня около приглашения — для шкалы пересечений.
            let events: [Busy]

            struct Busy: Equatable {
                let title: String
                let start: Date
                let end: Date
            }

            /// Те, что накладываются на приглашение.
            var clashes: [Busy] {
                guard !isAllDay else { return [] }
                return events.filter { $0.start < end && $0.end > start }
            }
        }
    }

    /// Кнопка, которая открывает превью здесь, а не отвечает.
    static let previewAction = "preview"

    /// Исполняется ли кнопка в самом вырезе: превью есть — показать его.
    func isLocal(_ action: Action) -> Bool {
        action.id == Self.previewAction && preview != nil
    }

    /// Ждёт ли уведомление ответа. От этого зависит и срок жизни плашки,
    /// и то, можно ли её перебить.
    var waitsForAnswer: Bool { !actions.isEmpty && !isOptional }

    static let maxActions = 2
    /// Потолок срока: присланное уведомление не имеет права занять вырез
    /// надолго, если ответа у него не спрашивают.
    static let maxHold: TimeInterval = 120

    /// Разбор присланного словаря.
    ///
    /// Возвращает `nil` на всём, что не разобралось, и пишет причину
    /// в журнал: молчаливый отказ выглядел бы как «уведомления не работают»,
    /// а чинить в чужом скрипте пришлось бы наугад.
    init?(json: [String: Any], id: String) {
        guard let title = (json["title"] as? String)?.trimmed, !title.isEmpty else {
            DebugLog.write("уведомление \(id): нет заголовка — пропущено")
            return nil
        }
        self.id = id
        self.title = title
        source = (json["source"] as? String)?.trimmed ?? t("Уведомление")
        // Значок сверяется со списком, а не берётся как есть: неизвестное имя
        // SF Symbols рисуется пустым местом, и плашка выходила бы безголовой.
        symbol = Self.symbol(named: json["icon"] as? String)
        replyPath = (json["reply"] as? String)?.trimmed

        let raw = (json["actions"] as? [[String: Any]]) ?? []
        actions = raw.prefix(Self.maxActions).compactMap(Action.init(json:))
        isOptional = (json["optional"] as? NSNumber)?.boolValue ?? false
        celebrates = (json["celebrate"] as? NSNumber)?.boolValue ?? false
        event = (json["event"] as? [String: Any]).flatMap(EventRef.init(json:))
        preview = (json["preview"] as? [String: Any]).flatMap(LetterPreview.init(json:))

        let asked = (json["hold"] as? NSNumber)?.doubleValue ?? 0
        // Спрашивающее уведомление ждёт без срока, даже если срок указан:
        // вопрос, пропавший сам, — это ответ, которого никто не давал.
        // Кнопки-предложения (`optional`) — не вопрос: у них срок как у всех.
        hold = actions.isEmpty || isOptional
            ? min(max(asked > 0 ? asked : (actions.isEmpty ? 6 : 10), 1), Self.maxHold)
            : .infinity
    }

    /// Прямая сборка — для проверок и для своих уведомлений изнутри.
    init(
        id: String,
        source: String,
        title: String,
        symbol: String = "bell.badge",
        hold: TimeInterval = 6,
        actions: [Action] = [],
        replyPath: String? = nil,
        isOptional: Bool = false,
        celebrates: Bool = false,
        event: EventRef? = nil,
        preview: LetterPreview? = nil
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.symbol = symbol
        self.hold = actions.isEmpty || isOptional ? hold : .infinity
        self.actions = Array(actions.prefix(Self.maxActions))
        self.replyPath = replyPath
        self.isOptional = isOptional
        self.celebrates = celebrates
        self.event = event
        self.preview = preview
    }

    /// Встреча из своего календаря, о которой эта плашка, — если она там есть.
    ///
    /// Сверка по названию и началу, а не по идентификатору: у одной встречи,
    /// прочитанной через macOS и через Exchange напрямую, идентификаторы
    /// разные. Минута люфта — на округление времени сервером.
    func sameMeeting(in items: [CalendarItem]) -> CalendarItem? {
        guard let event else { return nil }
        let title = Self.normalized(event.title)
        return items.first { item in
            item.source == .event && !item.isAllDay
                && abs(item.start.timeIntervalSince(event.start)) < 60
                && Self.normalized(item.title) == title
        }
    }

    private static func normalized(_ title: String) -> String {
        title.trimmed.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Значки, которые разрешено просить по имени.
    ///
    /// Список, а не свободное имя: `Image(systemName:)` на неизвестном имени
    /// рисует пустоту, и отличить опечатку от «так и задумано» было бы нечем.
    static let icons: [String: String] = [
        "bell": "bell.badge",
        "question": "questionmark.circle.fill",
        "build": "hammer.fill",
        "code": "chevron.left.forwardslash.chevron.right",
        "ai": "sparkles",
        "check": "checkmark",
        "cross": "xmark",
        "warning": "exclamationmark.triangle.fill",
        "download": "arrow.down.circle.fill",
        "message": "bubble.left.fill",
        "phone": "phone.fill",
        // Для Trudaybook: приглашение и встреча, отложенное, видеосвязь, почта.
        "calendar": "calendar",
        "clock": "clock.fill",
        "video": "video.fill",
        "mail": "envelope.fill",
        "archive": "archivebox.fill",
        // Письмо: открыть в почте или прочитать прямо здесь, и быстрые
        // действия превью.
        "open": "arrow.up.forward.app",
        "eye": "eye.fill",
        "replyall": "arrowshape.turn.up.left.2.fill",
        "forward": "arrowshape.turn.up.right.fill",
        "snooze": "alarm",
    ]

    static func symbol(named name: String?) -> String {
        guard let name, let symbol = icons[name.lowercased()] else { return "bell.badge" }
        return symbol
    }
}

extension ExternalNotice.Action {
    init?(json: [String: Any]) {
        guard let id = (json["id"] as? String)?.trimmed, !id.isEmpty,
              let title = (json["title"] as? String)?.trimmed, !title.isEmpty
        else { return nil }
        let positive = (json["positive"] as? NSNumber)?.boolValue ?? (id == "yes")
        // Значок у кнопки чаще всего не указывают вовсе, и брать тогда
        // общий колокольчик нельзя: в паре кнопок он не отличает согласие
        // от отказа. Поймано снимком — «Отклонить» вышло со звоночком.
        let named = (json["icon"] as? String)?.trimmed
        self.init(
            id: id,
            title: title,
            symbol: named.map(ExternalNotice.symbol(named:)) ?? (positive ? "checkmark" : "xmark"),
            isPositive: positive,
            opensApp: (json["opens"] as? NSNumber)?.boolValue ?? false
        )
    }

    /// Согласие и отказ — самая частая пара, и выписывать её в каждом хуке
    /// значило бы разводить подписи по чужим скриптам.
    static let yes = ExternalNotice.Action(
        id: "yes", title: t("Принять"), symbol: "checkmark", isPositive: true
    )
    static let no = ExternalNotice.Action(
        id: "no", title: t("Отклонить"), symbol: "xmark", isPositive: false
    )
}

extension ExternalNotice.LetterPreview {
    /// Потолки — чтобы чужой файл не раздул панель: текст письма
    /// показывается началом, целиком его читают в почте.
    init?(json: [String: Any]) {
        func field(_ key: String, _ limit: Int) -> String {
            String(((json[key] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
        }
        let text = field("text", 4000)
        let subject = field("subject", 300)
        guard !text.isEmpty || !subject.isEmpty else { return nil }
        let actions = ((json["actions"] as? [[String: Any]]) ?? [])
            .prefix(Self.maxActions)
            .compactMap(ExternalNotice.Action.init(json:))
        self.init(from: field("from", 200), subject: subject, text: text, date: field("date", 60),
                  actions: Array(actions),
                  meeting: (json["meeting"] as? [String: Any]).flatMap(Meeting.init(json:)))
    }
}

extension ExternalNotice.LetterPreview.Meeting {
    /// Время — ISO 8601; встреч рядом не больше двенадцати, дольше суток
    /// и перевёрнутые отбрасываются.
    init?(json: [String: Any]) {
        let iso = ISO8601DateFormatter()
        func date(_ value: Any?) -> Date? { (value as? String).flatMap(iso.date(from:)) }
        guard let start = date(json["start"]), let end = date(json["end"]), end > start,
              end.timeIntervalSince(start) <= 86_400 * 14 else { return nil }
        let events: [Busy] = ((json["events"] as? [[String: Any]]) ?? []).prefix(12).compactMap { item in
            guard let from = date(item["start"]), let to = date(item["end"]), to > from,
                  to.timeIntervalSince(from) <= 86_400 else { return nil }
            let title = String(((item["title"] as? String) ?? "").prefix(120))
            return Busy(title: title, start: from, end: to)
        }
        self.init(
            start: start, end: end,
            isAllDay: (json["allDay"] as? NSNumber)?.boolValue ?? false,
            location: String(((json["location"] as? String) ?? "").prefix(200)),
            events: events
        )
    }
}

extension ExternalNotice.EventRef {
    init?(json: [String: Any]) {
        guard let title = (json["title"] as? String)?.trimmed, !title.isEmpty,
              let text = json["start"] as? String,
              let start = ISO8601DateFormatter().date(from: text)
        else { return nil }
        self.init(title: title, start: start)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
