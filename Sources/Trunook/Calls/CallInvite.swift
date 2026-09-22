import Foundation

/// Приложение, у которого вырез умеет ловить звонок.
///
/// Тот же приём, что и у встреч (`MeetingApps`): список известных
/// приложений с точными подписями кнопок. Вслепую эту таблицу писать
/// нельзя — подписи снимаются с живого звонка, и на встречах это уже
/// ловило нас дважды.
struct CallApp: Equatable {
    let bundleID: String
    /// Как называть в плашке: «Zoiper», «Telegram».
    let name: String
    /// Слова, по которым в окне узнаётся кнопка ответа. Сверяются целиком:
    /// рядом с «Ответить» у некоторых клиентов стоит «Ответить видео»,
    /// и наугад можно включить камеру вместо простого ответа.
    let answerTitles: [String]
    let declineTitles: [String]
    /// Слова в заголовке окна, по которым окно считается звонком.
    /// Пусто — годится любое окно приложения с кнопкой ответа.
    let windowHints: [String]

    /// Известные клиенты.
    ///
    /// Каждый добавляется только после снятия дерева с живого звонка
    /// (`swift scripts/debug-event.swift callDump`): у одного клиента
    /// кнопки лежат в окне, у другого подписи переведены, у третьего
    /// звонок приходит отдельным окном без заголовка.
    static let known: [CallApp] = [
        // Telephone — самый ходовой SIP-телефон на macOS. Сверено живым
        // звонком: входящий приходит отдельным окном «номер@сервер»
        // 300×145 с двумя кнопками — «Ответить» и «Отклонить». Главное
        // окно учётной записи («101@сервер») кнопки ответа не имеет
        // и звонком не считается.
        CallApp(
            bundleID: "com.tlphn.Telephone",
            name: "Telephone",
            answerTitles: ["Ответить", "Answer", "Принять"],
            declineTitles: ["Отклонить", "Decline", "Hang Up", "Отбой", "Завершить"],
            windowHints: []
        ),
        CallApp(
            bundleID: "com.zoiper.zoiper5",
            name: "Zoiper",
            answerTitles: ["Ответить", "Answer", "Accept"],
            declineTitles: ["Отклонить", "Отбой", "Decline", "Reject", "Hang up"],
            windowHints: ["Входящий", "Incoming"]
        ),
        CallApp(
            bundleID: "org.linphone.linphone",
            name: "Linphone",
            answerTitles: ["Ответить", "Answer", "Accept call"],
            declineTitles: ["Отклонить", "Decline", "Decline call"],
            windowHints: []
        ),
        CallApp(
            bundleID: "com.counterpath.bria",
            name: "Bria",
            answerTitles: ["Ответить", "Answer"],
            declineTitles: ["Отклонить", "Decline", "Reject"],
            windowHints: ["Incoming", "Входящий"]
        ),
        CallApp(
            bundleID: "com.3cx.desktopapp",
            name: "3CX",
            answerTitles: ["Ответить", "Answer"],
            declineTitles: ["Отклонить", "Reject", "Decline"],
            windowHints: []
        ),
        CallApp(
            bundleID: "ru.keepcoder.Telegram",
            name: "Telegram",
            answerTitles: ["Принять", "Accept"],
            declineTitles: ["Отклонить", "Decline"],
            windowHints: ["Звонок", "Call"]
        ),
    ]

    static func app(bundleID: String) -> CallApp? {
        known.first { $0.bundleID == bundleID }
    }

    /// Все идентификаторы — для подписки на запуск приложений.
    static var bundleIDs: [String] { known.map(\.bundleID) }

    /// Годится ли окно с таким заголовком под звонок.
    ///
    /// Заголовок — только подсказка: у Linphone окно звонка называется
    /// именем приложения, и отсекать по нему значило бы не поймать звонок
    /// вовсе. Решает наличие кнопки ответа, а заголовок лишь отсеивает
    /// заведомо чужие окна, когда клиент их подписывает.
    func looksLikeCall(window title: String) -> Bool {
        guard !windowHints.isEmpty else { return true }
        return windowHints.contains { title.localizedCaseInsensitiveContains($0) }
    }
}

/// Входящий звонок, замеченный в чужом приложении.
struct CallInvite: Equatable, Identifiable {
    let app: CallApp
    /// Кто звонит. Берётся из заголовка окна или из подписи над кнопками;
    /// пусто — «Входящий звонок» без имени: номер лучше не выдумывать.
    let caller: String
    /// Есть ли кнопка отбоя. Ответ есть всегда — иначе это не звонок.
    let canDecline: Bool

    var id: String { app.bundleID + "|" + caller }

    /// Кто звонит — из заголовка окна звонка.
    ///
    /// SIP-телефон подписывает окно адресом целиком: «79001234567@192.168.0.10»
    /// — так пришло с живого звонка в Telephone. Адрес сервера человеку
    /// ничего не говорит и съедает половину плашки, поэтому остаётся
    /// номер: часть до «@» и без приставки «sip:».
    static func caller(fromTitle title: String) -> String {
        var clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.lowercased().hasPrefix("sip:") { clean = String(clean.dropFirst(4)) }
        if let at = clean.firstIndex(of: "@"), at > clean.startIndex {
            clean = String(clean[..<at])
        }
        return clean
    }

    /// Строка в плашке: кто звонит и куда.
    ///
    /// Приложение называется нарочно: звонить может и телефон, и мессенджер,
    /// а отвечать человек будет в разных местах.
    var text: String {
        caller.isEmpty
            ? tf("Входящий звонок · %@", app.name)
            : tf("%@ · %@", caller, app.name)
    }
}
