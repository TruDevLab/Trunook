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
