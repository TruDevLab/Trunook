import Foundation
import Testing
@testable import Trunook

/// Уведомления, которые о чём-то спрашивают: присланные снаружи,
/// предложения модели, напоминания, звонки.
@Suite("Уведомления с ответом")
struct NotificationsTests {
    // MARK: - Присланное снаружи

    @Test("Вопрос без заголовка не показывается")
    func безЗаголовка() {
        #expect(ExternalNotice(json: ["source": "Сборка"], id: "1") == nil)
        #expect(ExternalNotice(json: ["title": "   "], id: "1") == nil)
    }

    @Test("Кнопок не больше двух: третья съела бы сам вопрос")
    func двеКнопки() {
        let notice = ExternalNotice(json: [
            "title": "Выкатывать?",
            "actions": [
                ["id": "yes", "title": "Да"],
                ["id": "no", "title": "Нет"],
                ["id": "later", "title": "Потом"],
            ],
        ], id: "1")
        #expect(notice?.actions.count == 2)
        #expect(notice?.actions.last?.id == "no")
    }

    @Test("Письмо с превью: кнопка «preview» открывает его здесь, а не отвечает")
    func превьюПисьма() throws {
        let notice = try #require(ExternalNotice(json: [
            "source": "Работа", "title": "Анна: Отчёт", "optional": true,
            "actions": [
                ["id": "open", "title": "Открыть в Trudaybook", "positive": true, "icon": "open"],
                ["id": "preview", "title": "Показать превью", "icon": "eye"],
            ],
            "preview": ["from": "Анна <anna@example.com>", "subject": "Отчёт",
                        "text": String(repeating: "т", count: 5000), "date": "сегодня, 14:05"],
        ], id: "1"))
        let preview = try #require(notice.preview)
        #expect(preview.subject == "Отчёт")
        #expect(preview.text.count == 4000)
        #expect(notice.actions.map(\.symbol) == ["arrow.up.forward.app", "eye.fill"])
        #expect(!notice.isLocal(notice.actions[0]))
        #expect(notice.isLocal(notice.actions[1]))

        #expect(preview.actions.isEmpty)
        #expect(notice.actions[0].opensApp == false)

        // Быстрые действия превью: не больше четырёх, «opens» — выводить ли вперёд.
        let quick = try #require(ExternalNotice(json: [
            "title": "Письмо",
            "preview": ["subject": "Отчёт", "actions": [
                ["id": "replyAll", "title": "Ответить всем", "icon": "replyAll", "opens": true],
                ["id": "archive", "title": "В архив", "icon": "archive"],
                ["id": "forward", "title": "Переслать", "icon": "forward", "opens": true],
                ["id": "snooze1h", "title": "Через 1 час", "icon": "snooze"],
                ["id": "лишнее", "title": "Пятое"],
            ]],
        ], id: "4")?.preview)
        #expect(quick.actions.map(\.id) == ["replyAll", "archive", "forward", "snooze1h"])
        #expect(quick.actions.map(\.opensApp) == [true, false, true, false])
        #expect(quick.actions.first?.symbol == "arrowshape.turn.up.left.2.fill")

        // Приглашение: встреча и соседи по шкале, пересечения считаются.
        let iso = ISO8601DateFormatter()
        let base = Date(timeIntervalSince1970: 1_790_000_000)
        func at(_ minutes: Int) -> String { iso.string(from: base.addingTimeInterval(TimeInterval(minutes * 60))) }
        let invite = try #require(ExternalNotice(json: [
            "title": "Приглашение",
            "preview": ["subject": "Разбор", "meeting": [
                "start": at(0), "end": at(60), "location": "Переговорная",
                "events": [
                    ["title": "Планёрка", "start": at(-60), "end": at(-30)],
                    ["title": "Созвон", "start": at(30), "end": at(90)],
                    ["title": "Сломанное", "start": at(10), "end": at(5)],
                ],
            ]],
        ], id: "5")?.preview?.meeting)
        #expect(invite.events.count == 2)
        #expect(invite.clashes.map(\.title) == ["Созвон"])
        let window = InvitationTimeline.window(invite)
        #expect(window.lowerBound <= base.addingTimeInterval(-3600))
        #expect(window.upperBound >= base.addingTimeInterval(7200))
        #expect(InvitationTimeline.lanes(invite.events + [.init(title: "Ещё", start: base.addingTimeInterval(2400), end: base.addingTimeInterval(4000))]).count == 2)

        // Без превью «preview» — обычное слово ответа: решает приславший.
        let bare = try #require(ExternalNotice(json: [
            "title": "Письмо", "actions": [["id": "preview", "title": "Показать"]],
        ], id: "2"))
        #expect(bare.preview == nil)
        #expect(!bare.isLocal(bare.actions[0]))
        // Пустое превью не превью.
        #expect(ExternalNotice(json: ["title": "т", "preview": ["from": "Анна"]], id: "3")?.preview == nil)
    }

    @Test("Значок кнопки без имени берётся по смыслу, а не общим колокольчиком")
    func значкиКнопок() {
        let notice = ExternalNotice(json: [
            "title": "Записать файл?",
            "actions": [["id": "yes", "title": "Да"], ["id": "no", "title": "Нет"]],
        ], id: "1")
        #expect(notice?.actions.first?.symbol == "checkmark")
        #expect(notice?.actions.last?.symbol == "xmark")
        // Неизвестное имя значка не рисуется пустотой, а заменяется общим.
        #expect(ExternalNotice.symbol(named: "нетТакого") == "bell.badge")
        #expect(ExternalNotice.symbol(named: "BUILD") == "hammer.fill")
    }

    @Test("Кнопки-предложения (optional) не держат вырез: срок как у простого уведомления")
    func кнопкиБезВопроса() {
        let mail = ExternalNotice(json: [
            "title": "Анна: Бюджет",
            "optional": true,
            "hold": 12,
            "actions": [["id": "reply", "title": "Ответить", "positive": true], ["id": "archive", "title": "В архив"]],
        ], id: "1")
        #expect(mail?.actions.count == 2)
        #expect(mail?.waitsForAnswer == false)
        #expect(mail?.hold == 12)
        // Без срока — десять секунд: успеть прочесть и нажать.
        let quiet = ExternalNotice(json: [
            "title": "Анна: Бюджет", "optional": true, "actions": [["id": "reply", "title": "Ответить"]],
        ], id: "2")
        #expect(quiet?.hold == 10)
    }

    @Test("Конфетти — только по явной просьбе, значки Trudaybook узнаются")
    func конфеттиИЗначки() {
        let done = ExternalNotice(json: ["title": "Всё разобрано", "celebrate": true, "icon": "check"], id: "1")
        #expect(done?.celebrates == true)
        #expect(ExternalNotice(json: ["title": "Письмо"], id: "2")?.celebrates == false)
        #expect(ExternalNotice(json: ["title": "Письмо", "celebrate": "да"], id: "3")?.celebrates == false)
        #expect(ExternalNotice.symbol(named: "calendar") == "calendar")
        #expect(ExternalNotice.symbol(named: "video") == "video.fill")
        #expect(ExternalNotice.symbol(named: "mail") == "envelope.fill")
    }

    @Test("Недописанный скрытый файл не забирается из папки")
    func скрытыйНеЗабирается() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("trunook-inbox-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let hidden = folder.appendingPathComponent(".пишется.json")
        let ready = folder.appendingPathComponent("готов.json")
        try Data(#"{"title": "Пол"#.utf8).write(to: hidden)
        try Data(#"{"title": "Готово"}"#.utf8).write(to: ready)
        NotifyInbox(folder: folder).drain()
        #expect(FileManager.default.fileExists(atPath: hidden.path))
        #expect(!FileManager.default.fileExists(atPath: ready.path))
    }

    @Test("Спрашивающее уведомление не истекает само, даже если просили срок")
    func срокУВопроса() {
        let ask = ExternalNotice(json: [
            "title": "Выкатывать?",
            "hold": 3,
            "actions": [["id": "yes", "title": "Да"]],
        ], id: "1")
        #expect(ask?.hold == .infinity)
        #expect(ask?.waitsForAnswer == true)

        // А сообщение без кнопок живёт свой срок и не дольше потолка.
        let said = ExternalNotice(json: ["title": "Готово", "hold": 9999], id: "2")
        #expect(said?.hold == ExternalNotice.maxHold)
        #expect(said?.waitsForAnswer == false)
    }

    @Test("Ответ пишется только в свои папки")
    func кудаПисатьОтвет() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(NotifyInbox.mayWrite(to: home.appendingPathComponent("ответ.txt")))
        #expect(NotifyInbox.mayWrite(to: URL(fileURLWithPath: "/tmp/ответ.txt")))
        // Своя временная папка на macOS лежит в «/var/folders/…/T/», а не
        // в «/tmp»: на этом уткнулась первая живая проверка скрипта.
        #expect(NotifyInbox.mayWrite(
            to: FileManager.default.temporaryDirectory.appendingPathComponent("ответ.txt")
        ))

        #expect(!NotifyInbox.mayWrite(to: URL(fileURLWithPath: "/etc/hosts")))
        #expect(!NotifyInbox.mayWrite(to: URL(fileURLWithPath: "/Applications/что-то")))
        // Путь «наружу» через «..» считается по-настоящему, а не по строке.
        #expect(!NotifyInbox.mayWrite(
            to: home.appendingPathComponent("../../etc/hosts")
        ))
    }

    // MARK: - Кнопки в плашке

    @Test("Ждущие плашки получают пару кнопок, сообщающие — нет")
    func ктоЖдётОтвета() {
        let notice = ExternalNotice(
            id: "1", source: "Сборка", title: "Выкатывать?", actions: [.yes, .no]
        )
        #expect(ActivityView.answer(for: .external(notice))?.count == 2)
        #expect(ActivityView.answer(for: .breakReminder(.water))?.count == 2)
        #expect(ActivityView.answer(for: .timer(text: "Время вышло"))?.count == 2)

        #expect(ActivityView.answer(for: .trackChanged) == nil)
        #expect(ActivityView.answer(for: .lowBattery(percentage: 10)) == nil)
        // Сообщение без кнопок не превращается в вопрос.
        let said = ExternalNotice(id: "2", source: "Сборка", title: "Готово")
        #expect(ActivityView.answer(for: .external(said)) == nil)
    }

    @Test("Звонок Trudaybook: свои подписи кнопок, не кнопки письма")
    func звонокTrudaybook() throws {
        let app = try #require(CallApp.app(bundleID: "com.trudaybook.Trudaybook"))
        #expect(CallService.match(["Принять звонок"], app.answerTitles))
        #expect(CallService.match(["Decline call"], app.declineTitles))
        // «Ответить» в главном окне — ответ на письмо, а не на звонок.
        #expect(!CallService.match(["Ответить"], app.answerTitles))
        #expect(!CallService.match(["Отклонить"], app.declineTitles))
        #expect(app.looksLikeCall(window: "Ольга Смирнова"))
        #expect(CallInvite.caller(fromTitle: "Ольга Смирнова") == "Ольга Смирнова")
    }

    @Test("У звонка без отбоя одна кнопка, а не мёртвая вторая")
    func звонокБезОтбоя() {
        let app = CallApp(
            bundleID: "com.example.phone", name: "Телефон",
            answerTitles: ["Ответить"], declineTitles: ["Отклонить"], windowHints: []
        )
        let withDecline = CallInvite(app: app, caller: "+7 900", canDecline: true)
        let without = CallInvite(app: app, caller: "+7 900", canDecline: false)
        #expect(ActivityView.answer(for: .incomingCall(withDecline))?.count == 2)
        #expect(ActivityView.answer(for: .incomingCall(without))?.count == 1)
    }

    @Test("Место под кнопки считается по их числу")
    func местоПодКнопки() {
        let one = ActivityView.answerRoom(for: .incomingCall(
            CallInvite(app: CallApp.known[0], caller: "", canDecline: false)
        ))
        let two = ActivityView.answerRoom(for: .breakReminder(.rest))
        #expect(one > 0)
        #expect(two > one)
        // У плашки без кнопок места под них не отмеряется вовсе.
        #expect(ActivityView.answerRoom(for: .trackChanged) == 0)
    }

    @Test("Встреча, которую Trunook видит сам, узнаётся по названию и началу")
    func своиВстречи() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let own = CalendarItem(
            id: "ek-1", title: "Ретро - разбор дефектов", start: start, end: nil,
            isAllDay: false, source: .event, link: nil, colorComponents: nil
        )
        func notice(_ title: String, _ start: Date) -> ExternalNotice? {
            ExternalNotice(json: [
                "source": "Exchange", "title": "«\(title)» через 5 мин",
                "event": ["title": title, "start": ISO8601DateFormatter().string(from: start)],
            ], id: "1")
        }
        #expect(notice("Ретро - разбор дефектов", start)?.sameMeeting(in: [own]) == own)
        // Регистр и лишние пробелы — та же встреча.
        #expect(notice(" ретро -  разбор дефектов ", start.addingTimeInterval(30))?.sameMeeting(in: [own]) == own)
        // Другое время или название — другая встреча.
        #expect(notice("Ретро - разбор дефектов", start.addingTimeInterval(3600))?.sameMeeting(in: [own]) == nil)
        #expect(notice("Планерка", start)?.sameMeeting(in: [own]) == nil)
        // Без описания встречи сверять нечего.
        #expect(ExternalNotice(json: ["title": "«Ретро - разбор дефектов» через 5 мин"], id: "2")?
            .sameMeeting(in: [own]) == nil)
    }

    // MARK: - Очерёдность

    @Test("Звонок и вопрос важнее смены трека, но ждут не дольше срока")
    func приоритеты() {
        let call = Activity(kind: .incomingCall(
            CallInvite(app: CallApp.known[0], caller: "", canDecline: true)
        ))
        let track = Activity(kind: .trackChanged)
        let meeting = Activity(kind: .meeting(
            item: CalendarItem(
                id: "1", title: "Созвон", start: Date(), end: nil,
                isAllDay: false, source: .event, link: nil, colorComponents: nil
            ),
            minutesBefore: 5
        ))
        #expect(call.priority > meeting.priority)
        #expect(meeting.priority > track.priority)

        // Ни одна плашка не висит вечно: вечная заняла бы вырез насмерть
        // и своим приоритетом отбросила бы и встречу, и вышедшее время.
        #expect(call.duration.isFinite)
        let ask = ExternalNotice(
            id: "1", source: "Сборка", title: "Выкатывать?", actions: [.yes]
        )
        #expect(Activity(kind: .external(ask)).duration.isFinite)
    }

    // MARK: - Телефоны

    @Test("Окно звонка узнаётся по подсказкам, а без них годится любое")
    func окноЗвонка() {
        let strict = CallApp(
            bundleID: "a", name: "A", answerTitles: ["Ответить"],
            declineTitles: [], windowHints: ["Входящий"]
        )
        #expect(strict.looksLikeCall(window: "Входящий звонок"))
        #expect(strict.looksLikeCall(window: "ВХОДЯЩИЙ ЗВОНОК"))
        #expect(!strict.looksLikeCall(window: "Настройки"))

        // Без подсказок решает не заголовок, а найденная кнопка ответа:
        // у части клиентов окно звонка называется именем приложения.
        let loose = CallApp(
            bundleID: "b", name: "B", answerTitles: ["Ответить"],
            declineTitles: [], windowHints: []
        )
        #expect(loose.looksLikeCall(window: "Linphone"))
    }

    @Test("Из адреса SIP в плашку идёт номер, а не сервер")
    func номерЗвонящего() {
        // Так подписано окно входящего в Telephone на живом звонке.
        #expect(CallInvite.caller(fromTitle: "79001234567@192.168.0.10") == "79001234567")
        #expect(CallInvite.caller(fromTitle: "sip:101@pbx.local") == "101")
        #expect(CallInvite.caller(fromTitle: "  Мама  ") == "Мама")
        // «@» в начале — не адрес: резать там нечего.
        #expect(CallInvite.caller(fromTitle: "@канал") == "@канал")
    }

    @Test("Подписи кнопок сверяются целиком, а не вхождением")
    func подписиЦеликом() {
        let app = CallApp.known[0]
        #expect(CallService.match(["Ответить"], app.answerTitles))
        #expect(CallService.match(["ОТВЕТИТЬ"], app.answerTitles))
        // «Ответить видео» — не «Ответить»: ответа с камерой человек
        // не просил, и включать её за него нельзя.
        #expect(!CallService.match(["Ответить видео"], app.answerTitles))
    }
}
