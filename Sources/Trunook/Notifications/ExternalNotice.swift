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
        isOptional: Bool = false
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.symbol = symbol
        self.hold = actions.isEmpty || isOptional ? hold : .infinity
        self.actions = Array(actions.prefix(Self.maxActions))
        self.replyPath = replyPath
        self.isOptional = isOptional
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
            isPositive: positive
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

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
