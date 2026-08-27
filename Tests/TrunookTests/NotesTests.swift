import AppKit
import Foundation
import Testing
@testable import Trunook

/// Заметки: хранилище, поиск, имена и выгрузка.
///
/// Всё — на временной базе. У истории буфера путь к файлу статический,
/// и проверить её, не тронув настоящую базу человека, нельзя вовсе; здесь
/// путь приходит в `init` именно поэтому.
@Suite("Заметки")
struct NotesTests {
    // MARK: - Обвязка

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("trunook-notes-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
    }

    private func store() -> NotesStore {
        NotesStore(url: temporaryURL())
    }

    /// Настройки с выключенной моделью: иначе тест полез бы в сеть
    /// за именем заметки, и его исход зависел бы от того, запущена ли Ollama.
    private func settings() -> Settings {
        let defaults = UserDefaults(suiteName: "trunook-tests-\(UUID().uuidString)")!
        let settings = Settings(defaults: defaults)
        settings.ollamaEnabled = false
        settings.notesTitleByModel = false
        return settings
    }

    private func service() -> NotesService {
        let settings = self.settings()
        return NotesService(
            store: store(),
            titler: NoteTitler(settings: settings),
            settings: settings
        )
    }

    private func plain(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: Note.bodyFontSize),
        ])
    }

    private let ru = Locale(identifier: "ru_RU")

    // MARK: - Хранилище

    @Test("Заметка ложится, читается и удаляется")
    func запискаИЧтение() throws {
        let store = self.store()
        let text = plain("Купить билеты")
        let rtf = try #require(
            text.rtf(from: NSRange(location: 0, length: text.length), documentAttributes: [:])
        )
        let note = Note(
            id: Note.unsaved,
            title: "Проба",
            rtf: rtf,
            plain: text.string,
            createdAt: Date(),
            updatedAt: Date(),
            origin: .typed,
            titleByModel: false
        )

        let id = try #require(store.insert(note))
        #expect(store.count == 1)

        let read = store.note(id: id)
        #expect(read?.title == "Проба")
        #expect(read?.plain == "Купить билеты")
        // Оформление обязано пережить дорогу через базу: ради него весь RTF
        // и хранится.
        #expect(read?.attributed.string == "Купить билеты")

        store.delete(id: id)
        #expect(store.count == 0)
    }

    @Test("Правка меняет текст, но не время создания")
    func правкаНеТрогаетСоздание() throws {
        let service = self.service()
        let born = Date(timeIntervalSince1970: 1_000_000)
        let saved = try #require(service.save(plain("Первый текст"), origin: .typed, now: born))

        let later = born.addingTimeInterval(3_600)
        let updated = service.save(plain("Второй текст"), origin: .typed, editing: saved.id, now: later)

        #expect(updated?.plain == "Второй текст")
        #expect(updated?.createdAt == born)
        #expect(updated?.updatedAt == later)
        #expect(service.total == 1, "правка не должна плодить вторую заметку")
    }

    @Test("Пустую заметку не сохраняем")
    func пустуюНеСохраняем() {
        let service = self.service()
        #expect(service.save(plain("   \n\t "), origin: .typed) == nil)
        #expect(service.total == 0)
    }

    @Test("Одинаковые заметки не сливаются в одну")
    func повторНеСливается() {
        // У буфера повтор поднимает прежнюю запись наверх — там это верно:
        // человек скопировал то же самое. Здесь наоборот: записать дважды —
        // осознанное действие, и слить их значило бы потерять одну.
        let service = self.service()
        service.save(plain("Одно и то же"), origin: .typed)
        service.save(plain("Одно и то же"), origin: .typed)
        #expect(service.total == 2)
    }

    // MARK: - Поиск

    @Test("Поиск находит по имени и по тексту")
    func поискПоИмениИТексту() {
        let store = self.store()
        insert(into: store, title: "Отпуск", text: "забронировать жильё")
        insert(into: store, title: "Работа", text: "созвон в четверг")

        #expect(store.search("отпуск").count == 1)
        #expect(store.search("созвон").count == 1)
        #expect(store.search("нетакого").isEmpty)
    }

    /// Ради этого случая и заведена отдельная сложенная колонка. Встроенный
    /// в SQLite `LIKE` складывает регистр только для латиницы, и по-русски
    /// поиск без неё молчит — выглядит это как «поиск сломан».
    @Test("Регистр кириллицы поиску не помеха")
    func регистрКириллицы() {
        let store = self.store()
        insert(into: store, title: "Заметка", text: "Привет, Мир")

        #expect(store.search("привет").count == 1, "нижний регистр запроса не нашёл верхний в тексте")
        #expect(store.search("ПРИВЕТ").count == 1, "верхний регистр запроса не нашёл текст")
        #expect(store.search("мИр").count == 1)
    }

    @Test("Слова запроса ищутся порознь")
    func словаПорознь() {
        let store = self.store()
        insert(into: store, title: "Кино", text: "купить билеты в кино на пятницу")

        // Порядок слов в запросе не тот, что в заметке, — и это нормально:
        // человек помнит слова, а не фразу целиком.
        #expect(store.search("кино купить").count == 1)
        #expect(store.search("купить самолёт").isEmpty, "нашлось по одному слову из двух")
    }

    @Test("Процент в запросе — буква, а не образец")
    func процентЭтоБуква() {
        let store = self.store()
        insert(into: store, title: "Скидка", text: "скидка 50% до пятницы")
        insert(into: store, title: "Прочее", text: "совсем про другое")

        // Без экранирования один этот символ нашёл бы обе заметки.
        #expect(store.search("50%").count == 1)
        #expect(store.search("%").count == 1)
    }

    @Test("Пустой запрос отдаёт всё")
    func пустойЗапросОтдаётВсё() {
        let store = self.store()
        insert(into: store, title: "Раз", text: "один")
        insert(into: store, title: "Два", text: "два")

        #expect(store.search("").count == 2)
        #expect(store.search("   ").count == 2)
    }

    // MARK: - Запасное имя

    @Test("Запасное имя — дата и начало текста")
    func запасноеИмя() {
        let date = Date(timeIntervalSince1970: 1_756_000_000)
        let title = NoteTitler.fallback(for: "Купить билеты\nи паспорт", at: date, locale: ru)

        #expect(title.contains("Купить билеты"), "в имени нет начала текста: \(title)")
        #expect(!title.contains("паспорт"), "в имя попала вторая строка: \(title)")
        // Дата стоит первой: заметок за день бывает несколько, и начинаются
        // они похоже — различает их только дата.
        #expect(!title.hasPrefix("Купить"), "имя началось не с даты: \(title)")
    }

    @Test("Пустой текст оставляет в имени одну дату")
    func имяБезТекста() {
        let title = NoteTitler.fallback(for: "  \n ", at: Date(), locale: ru)
        #expect(!title.isEmpty)
        #expect(!title.contains("—"), "тире без текста после него: \(title)")
    }

    @Test("Длинная строка обрезается по слову")
    func обрезкаПоСлову() {
        let long = "Купить билеты на самолёт до Владивостока и обратно с пересадкой"
        let cut = NoteTitler.truncated(long, to: 20)

        #expect(cut.count <= 21, "обрезка длиннее потолка: \(cut)")
        #expect(cut.hasSuffix("…"))
        // По слову, а не по букве: «до Влади…» читается, «до Владив» — нет.
        #expect(!cut.contains("Владивосток"))
        #expect(cut.hasPrefix("Купить билеты"))
    }

    // MARK: - Чистка ответа модели

    @Test("Кавычки и точка с ответа снимаются")
    func чисткаКавычек() {
        #expect(NoteTitler.clean("«Покупка билетов»") == "Покупка билетов")
        #expect(NoteTitler.clean("\"Покупка билетов\".") == "Покупка билетов")
        #expect(NoteTitler.clean("**Покупка билетов**") == "Покупка билетов")
        #expect(NoteTitler.clean("## Покупка билетов") == "Покупка билетов")
    }

    @Test("Вводная фраза срезается")
    func чисткаВводной() {
        #expect(NoteTitler.clean("Название: Покупка билетов") == "Покупка билетов")
        #expect(NoteTitler.clean("Вот подходящее название: Покупка билетов") == "Покупка билетов")
        #expect(NoteTitler.clean("Title: Buying tickets") == "Buying tickets")
    }

    /// Двоеточие само по себе признаком вводной фразы служить не может.
    @Test("Название с двоеточием остаётся целым")
    func двоеточиеВНазвании() {
        #expect(NoteTitler.clean("Отпуск: что взять") == "Отпуск: что взять")
    }

    @Test("Из многословного ответа берётся первая строка")
    func перваяСтрока() {
        let answer = """
            Покупка билетов

            Это название отражает суть заметки, потому что…
            """
        #expect(NoteTitler.clean(answer) == "Покупка билетов")
    }

    @Test("Пустой ответ не даёт пустого имени")
    func пустойОтвет() {
        // Прежнее имя лучше пустой строки в списке.
        #expect(NoteTitler.clean("") == nil)
        #expect(NoteTitler.clean("   \n  ") == nil)
        #expect(NoteTitler.clean("«»") == nil)
    }

    @Test("Слишком длинное имя обрезается")
    func длинноеИмя() throws {
        let answer = String(repeating: "слово ", count: 40)
        let title = try #require(NoteTitler.clean(answer))
        #expect(title.count <= NoteTitler.maxLength + 1)
    }

    // MARK: - Контекст для модели

    @Test("Без заметок контекста нет")
    func контекстаБезЗаметокНет() {
        #expect(service().contextText(budget: 10_000) == nil)
    }

    @Test("В контекст идут свежие первыми")
    func контекстСвежиеПервыми() throws {
        let service = self.service()
        let old = Date(timeIntervalSince1970: 1_000_000)
        service.save(plain("Самая старая мысль"), origin: .typed, now: old)
        service.save(plain("Самая свежая мысль"), origin: .typed, now: old.addingTimeInterval(7_200))

        let context = try #require(service.contextText(budget: 10_000))
        let fresh = try #require(context.range(of: "свежая"))
        let stale = try #require(context.range(of: "старая"))
        #expect(fresh.lowerBound < stale.lowerBound, "старая заметка встала выше свежей")
    }

    @Test("Об обрезанном контексте сказано вслух")
    func контекстСообщаетОбОбрезке() throws {
        let service = self.service()
        let base = Date(timeIntervalSince1970: 1_000_000)
        for index in 0..<10 {
            service.save(
                plain(String(repeating: "текст ", count: 100) + "\(index)"),
                origin: .typed,
                now: base.addingTimeInterval(Double(index) * 60)
            )
        }

        let context = try #require(service.contextText(budget: 1_500))
        #expect(context.count < 3_000, "потолок контекста не сработал: \(context.count) символов")
        // Молчаливая обрезка — худшее, что здесь может быть: ответ по огрызку
        // выглядит как неверный, и человек винит модель.
        #expect(context.contains("из 10"), "в контексте нет отметки об обрезке")
    }

    @Test("Одна заметка длиннее потолка всё равно попадает")
    func однаДлиннаяВлезает() throws {
        let service = self.service()
        service.save(plain(String(repeating: "очень длинная мысль ", count: 500)), origin: .typed)

        let context = try #require(service.contextText(budget: 1_000))
        #expect(context.contains("длинная"), "единственная заметка выпала из контекста целиком")
    }

    // MARK: - Выгрузка

    @Test("Оформление доходит до Markdown")
    func выгрузкаОформления() {
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "Заголовок\n", attributes: [
            .font: NSFont.boldSystemFont(ofSize: Note.headingFontSize),
        ]))
        text.append(NSAttributedString(string: "обычный ", attributes: [
            .font: NSFont.systemFont(ofSize: Note.bodyFontSize),
        ]))
        text.append(NSAttributedString(string: "жирный", attributes: [
            .font: NSFont.boldSystemFont(ofSize: Note.bodyFontSize),
        ]))

        let markdown = NoteMarkdown.body(text)
        #expect(markdown.contains("## Заголовок"))
        #expect(markdown.contains("**жирный**"))
        // Звёздочки вокруг пробела разметкой не считаются ни одним
        // разборщиком и вылезли бы в файл как есть.
        #expect(!markdown.contains("** "))
    }

    @Test("Ссылка выгружается ссылкой")
    func выгрузкаСсылки() {
        let text = NSAttributedString(string: "сайт", attributes: [
            .font: NSFont.systemFont(ofSize: Note.bodyFontSize),
            .link: URL(string: "https://trunook.ru")!,
        ])
        #expect(NoteMarkdown.body(text) == "[сайт](https://trunook.ru)")
    }

    @Test("Имя файла переживает двоеточие в названии")
    func имяФайла() {
        // Имя заметки начинается со времени, а в нём двоеточие есть всегда:
        // в macOS это разделитель пути в старом смысле, и Finder показал бы
        // такое имя с косой чертой.
        let note = Note(
            id: 1,
            title: "25 августа, 14:30 — Купить билеты",
            rtf: Data(),
            plain: "Купить билеты",
            createdAt: Date(timeIntervalSince1970: 1_756_000_000),
            updatedAt: Date(),
            origin: .typed,
            titleByModel: false
        )
        let name = NoteMarkdown.fileName(for: note)

        #expect(!name.contains(":"))
        #expect(!name.contains("/"))
        #expect(name.hasSuffix(".md"))
        // Дата впереди, чтобы папка сортировалась по времени, а не по букве.
        #expect(name.hasPrefix("2025-"))
    }

    @Test("Выгружаются все заметки, ни одна не затирает другую")
    func выгрузкаВсех() throws {
        let service = self.service()
        let now = Date(timeIntervalSince1970: 1_756_000_000)
        // Одна минута на обе: имя файла собирается из даты, и без разведения
        // вторая легла бы поверх первой.
        service.save(plain("Первая мысль"), origin: .typed, now: now)
        service.save(plain("Вторая мысль"), origin: .typed, now: now)

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("trunook-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let result = service.exportAll(to: folder)
        #expect(result.written == 2)
        #expect(result.failed == 0)

        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(files.count == 2, "одна заметка затёрла другую: \(files)")
    }

    // MARK: - Чужие цвета

    /// Вставленное из браузера или документа приносит свой цвет. Чёрный текст
    /// на чёрной панели попросту не виден, а поменять его руками нечем —
    /// кнопки цвета в заметках нет. Заметка выглядела бы пустой, оставаясь
    /// непустой: беда тихая и оттого злая.
    @Test("Чужой цвет становится белым")
    func чужойЦветБелеет() throws {
        let text = NSMutableAttributedString(string: "чёрным по чёрному", attributes: [
            .font: NSFont.systemFont(ofSize: Note.bodyFontSize),
            .foregroundColor: NSColor.black,
            .backgroundColor: NSColor.yellow,
        ])
        let clean = RichTextEditor.normalized(text, tint: NSColor(Palette.assistant))

        let color = try #require(
            clean.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        )
        #expect(color == .white)
        #expect(clean.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil,
                "подложка осталась — на чёрной панели она видна прямоугольником")
    }

    @Test("Начертание чужого текста остаётся")
    func начертаниеОстаётся() throws {
        // Полужирный и курсив в чужом тексте — это его смысл, а не подгонка
        // под чужую тему. Снимать их значило бы терять содержание.
        let text = NSAttributedString(string: "важное", attributes: [
            .font: NSFont.boldSystemFont(ofSize: Note.bodyFontSize),
            .foregroundColor: NSColor.red,
        ])
        let clean = RichTextEditor.normalized(text, tint: NSColor(Palette.assistant))

        let font = try #require(clean.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.fontDescriptor.symbolicTraits.contains(.bold))
    }

    @Test("Ссылка остаётся своего цвета, а не белеет")
    func ссылкаНеБелеет() throws {
        // Побелей она вместе с остальным — и ссылка перестала бы отличаться
        // от обычного текста.
        let tint = NSColor(Palette.assistant)
        let text = NSAttributedString(string: "сайт", attributes: [
            .font: NSFont.systemFont(ofSize: Note.bodyFontSize),
            .foregroundColor: NSColor.blue,
            .link: URL(string: "https://trunook.ru")!,
        ])
        let clean = RichTextEditor.normalized(text, tint: tint)

        let color = try #require(
            clean.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        )
        #expect(color == tint)
    }

    // MARK: - Вёрстка

    private let metrics = NotchMetrics(notchWidth: 185, notchHeight: 32)

    /// Ширина крыла по тому же расчёту, что и в `NotchPanel`.
    private func wing(panelWidth: CGFloat, notchWidth: CGFloat) -> CGFloat {
        let outerInset = NotchStyle.bottomPadding + NotchStyle.shoulderInset
        return (panelWidth - notchWidth) / 2 - outerInset - NotchStyle.notchInset
    }

    /// Ходовые ширины чёлки: у каждой модели MacBook своя, и панель, ширина
    /// которой подобрана на одной, обрезает кнопку на другой.
    private let notchWidths: [CGFloat] = [160, 185, 200, 220]

    @Test("Окно вмещает обе панели")
    func окноВмещаетПанели() {
        // Панель, не вписанная в потолок окна, рисуется — и обрезается
        // по его краю. Заметить это можно только снимком.
        #expect(metrics.windowSize.width >= NotesPanel.width(notchWidth: 185))
        #expect(metrics.windowSize.height >= NotesPanel.height(
            notchHeight: 32,
            rows: NotesPanel.visibleRows
        ))
        #expect(metrics.windowSize.width >= AssistantPanel.width(notchWidth: 185))
        #expect(metrics.windowSize.height >= AssistantPanel.height(
            notchHeight: 32,
            notchWidth: 185
        ))
    }

    @Test("Крылья вмещают свои кнопки при любой ширине чёлки")
    func крыльяВмещаютКнопки() {
        for notchWidth in notchWidths {
            // В крыле панели модели три кнопки разом: остановка голоса,
            // список заметок и крестик. Поиск по заметкам уехал вниз,
            // к кнопке отправки.
            let assistant = wing(
                panelWidth: AssistantPanel.width(notchWidth: notchWidth),
                notchWidth: notchWidth
            )
            #expect(
                assistant >= NotchStyle.wingRow(buttons: AssistantPanel.wingButtons),
                "чёлка \(notchWidth): крыло панели модели \(assistant) не вмещает кнопки"
            )

            // В крыле списка две: выгрузка и крестик.
            let list = wing(
                panelWidth: NotesPanel.width(notchWidth: notchWidth),
                notchWidth: notchWidth
            )
            #expect(
                list >= NotchStyle.wingRow(buttons: 2),
                "чёлка \(notchWidth): крыло списка \(list) не вмещает две кнопки"
            )
        }
    }

    /// Полоса действий в режиме заметки самая тесная: переключатель режима,
    /// четыре кнопки оформления и главная кнопка в один ряд.
    @Test("Главной кнопке остаётся место в самой тесной полосе")
    func главнойКнопкеЕстьМесто() {
        for notchWidth in notchWidths {
            let left = AssistantPanel.primaryWidth(notchWidth: notchWidth)
            // Восемьдесят точек — это значок и слово вроде «Сохранить».
            // Меньше — и подпись начнёт сжиматься, а кнопка перестанет
            // читаться как главная.
            #expect(
                left >= 80,
                "чёлка \(notchWidth): главной кнопке осталось \(left) точек"
            )
        }
    }

    /// В разговоре рядом с кнопкой отправки нет ни одной другой кнопки,
    /// и растянутая по всему остатку строки она читалась как полоса,
    /// а не как кнопка.
    @Test("Кнопка отправки не шире половины строки, но подпись вмещает")
    func кнопкаОтправкиПоловинная() {
        for notchWidth in notchWidths {
            let available = AssistantPanel.width(notchWidth: notchWidth)
                - 2 * (AssistantPanel.bodyPadding + NotchStyle.shoulderInset)
            let send = AssistantPanel.sendWidth(notchWidth: notchWidth)

            #expect(send >= 80, "чёлка \(notchWidth): подпись не поместится в \(send)")
            #expect(
                2 * send + ModeSwitch.width + AssistantPanel.actionSpacing <= available + 0.5,
                "чёлка \(notchWidth): кнопка \(send) шире половины остатка"
            )
        }
    }

    /// Нижняя полоса разговора: переключатель режима, значок поиска
    /// по заметкам и кнопка отправки. Между режимом и парой справа должна
    /// оставаться распорка — иначе они слипнутся в сплошную полосу.
    @Test("Полоса разговора вмещает всё, и остаётся зазор")
    func полосаРазговораВмещает() {
        for notchWidth in notchWidths {
            let slack = AssistantPanel.conversationSlack(notchWidth: notchWidth)
            #expect(
                slack >= 0,
                "чёлка \(notchWidth): полоса разговора переполнена на \(-slack)"
            )
        }
    }

    @Test("Переключатель режима вмещает оба названия")
    func переключательВмещаетНазвания() {
        let font = NSFont.systemFont(ofSize: NotchStyle.font(11), weight: .medium)
        for mode in NotePanelMode.allCases {
            let text = TextMeasure.width(mode.title, font: font)
            // Значок, зазор и поля по краям сегмента.
            let needed = text + 12 + 4 + 12
            #expect(
                needed <= ModeSwitch.segmentWidth,
                "«\(mode.title)» требует \(needed) при сегменте \(ModeSwitch.segmentWidth)"
            )
        }
    }

    /// В режиме заметки области ответа нет вовсе, и место, которое она
    /// занимала, уходит полю. Панель от этого не должна становиться ниже.
    @Test("Заметка не ниже разговора")
    func заметкаНеНиже() {
        let model = AssistantPanel.height(notchHeight: 32, notchWidth: 185, mode: .model)
        let note = AssistantPanel.height(notchHeight: 32, notchWidth: 185, mode: .note)
        #expect(note > 0 && model > 0)
        #expect(metrics.windowSize.height >= max(model, note))
    }

    /// Высота строки ответа была выписана числом — и оказалась меньше
    /// настоящей: панель выходила короче содержимого, и последняя строка
    /// обрезалась пополам. Теперь она считается из шрифта.
    @Test("Строка ответа не ниже своего шрифта")
    func строкаОтветаНеНиже() {
        let font = AssistantPanel.answerFont
        let real = font.ascender - font.descender + font.leading
        #expect(
            AssistantPanel.lineHeight >= real,
            "строка \(AssistantPanel.lineHeight) ниже шрифта \(real) — текст обрежется"
        )
    }

    @Test("Список заметок не растёт бесконечно")
    func списокПрокручивается() {
        // Список, который может пополниться, обязан прокручиваться с самого
        // начала: иначе однажды он вырастет и обрежется краем окна.
        let five = NotesPanel.height(notchHeight: 32, rows: NotesPanel.visibleRows)
        let сто = NotesPanel.height(notchHeight: 32, rows: 100)
        #expect(five == сто)
    }

    // MARK: -

    private func insert(into store: NotesStore, title: String, text: String) {
        let rich = plain(text)
        guard let rtf = rich.rtf(
            from: NSRange(location: 0, length: rich.length),
            documentAttributes: [:]
        ) else { return }
        let note = Note(
            id: Note.unsaved,
            title: title,
            rtf: rtf,
            plain: text,
            createdAt: Date(),
            updatedAt: Date(),
            origin: .typed,
            titleByModel: false
        )
        _ = store.insert(note)
    }
}

/// Растущее поле вопроса и отправка чужого текста в заметки.
///
/// Поле было однострочным, и набранное сверх строки уезжало за правый край:
/// текст дальше не набирался вовсе. Высота теперь зависит от текста — а вслед
/// за ней и высота панели, и потолок окна. Оба расчёта тут и проверяются:
/// разойдись они, панель обрезало бы краем окна, и увидеть это можно было бы
/// только снимком.
@Suite("Поле вопроса и отправка в заметки")
struct AssistantInputTests {
    private let notchWidth: CGFloat = 185
    private let metrics = NotchMetrics(notchWidth: 185, notchHeight: 32)

    private var textWidth: CGFloat {
        AssistantPanel.questionTextWidth(notchWidth: 185)
    }

    @Test("Пустое поле — в одну строку")
    func пустоеПолеОдностроное() {
        #expect(GrowingTextField.height(for: "", textWidth: textWidth)
            == GrowingTextField.minHeight)
        #expect(GrowingTextField.height(for: "коротко", textWidth: textWidth)
            == GrowingTextField.minHeight)
    }

    @Test("Поле растёт вместе с текстом")
    func полеРастёт() {
        let one = GrowingTextField.height(for: "строка", textWidth: textWidth)
        let three = GrowingTextField.height(for: "раз\nдва\nтри", textWidth: textWidth)
        #expect(three > one, "три строки \(three) не выше одной \(one)")
    }

    /// ⇧Enter в конце текста ставит курсор на новую строку — и поле обязано
    /// под неё подрасти. Пустая последняя строка в замер текста не попадает:
    /// после последнего перевода строки не нарисовано ничего, и поле стояло
    /// на месте ровно в тот миг, когда его и просили подрасти.
    @Test("Перевод строки в конце тоже считается")
    func пустаяПоследняяСтрока() {
        let without = GrowingTextField.height(for: "строка", textWidth: textWidth)
        let with = GrowingTextField.height(for: "строка\n", textWidth: textWidth)
        #expect(with > without, "после ⇧Enter поле \(with) не выше прежнего \(without)")
    }

    @Test("Поле упирается в потолок и дальше прокручивается")
    func потолокПоля() {
        let huge = String(repeating: "длинное слово ", count: 400)
        let height = GrowingTextField.height(for: huge, textWidth: textWidth)
        #expect(height == GrowingTextField.maxHeight)
        #expect(GrowingTextField.maxHeight > GrowingTextField.minHeight)
    }

    /// Высота строки выписанная числом однажды уже оказалась меньше
    /// настоящей, и последняя строка обрезалась пополам. Здесь она
    /// считается из шрифта — проверяем, что не меньше него.
    @Test("Строка поля не ниже своего шрифта")
    func строкаНеНижеШрифта() {
        let font = GrowingTextField.font
        let real = font.ascender - font.descender + font.leading
        #expect(GrowingTextField.lineHeight >= real)
    }

    @Test("Панель растёт вместе с полем")
    func панельРастёт() {
        let empty = AssistantPanel.height(notchHeight: 32, notchWidth: notchWidth)
        let long = AssistantPanel.height(
            notchHeight: 32,
            notchWidth: notchWidth,
            question: "раз\nдва\nтри\nчетыре"
        )
        #expect(long > empty, "панель с многострочным вопросом \(long) не выше пустой \(empty)")
    }

    /// Потолок окна обязан вмещать самую высокую панель — с полем,
    /// доросшим до своего предела. Содержимое, переросшее окно, обрезается
    /// краем, и заметить это можно только снимком.
    @Test("Окно вмещает панель с выросшим полем")
    func окноВмещаетВыросшуюПанель() {
        let grown = AssistantPanel.height(
            notchHeight: metrics.notchHeight,
            notchWidth: metrics.notchWidth,
            question: String(repeating: "строка вопроса\n", count: 20)
        )
        #expect(metrics.windowSize.height >= grown,
                "панель \(grown) выше окна \(metrics.windowSize.height)")
        #expect(AssistantPanel.tallest(
            notchHeight: metrics.notchHeight,
            notchWidth: metrics.notchWidth
        ) >= grown)
    }

    // MARK: - Запись буфера в заметки

    private func entry(_ kind: ClipboardEntry.Kind, _ text: String) -> ClipboardEntry {
        ClipboardEntry(id: 7, kind: kind, text: text, copiedAt: Date())
    }

    @Test("В заметки уходит текст, и только он")
    func вЗаметкиТолькоТекст() {
        #expect(entry(.text, "мысль").notesText == "мысль")
        // Целиком, а не однострочной выжимкой: в заметке абзацы нужны
        // такими, какими их скопировали.
        #expect(entry(.text, "первый\nвторой").notesText == "первый\nвторой")
        #expect(entry(.text, "   \n  ").notesText == nil)
        #expect(entry(.image, "снимок").notesText == nil)
        #expect(entry(.files, "/tmp/один\n/tmp/два").notesText == nil)
    }

    /// Кнопка «в заметки» есть только у скопированного текста и только когда
    /// заметки включены. От неё зависит ширина плашки — разойдись счёт
    /// кнопок с рисунком, последнюю обрезало бы краем.
    @Test("Кнопка на плашке появляется только у текста")
    func кнопкаНаПлашке() {
        let text = Activity.Kind.clipboard(entry: entry(.text, "мысль"))
        let image = Activity.Kind.clipboard(entry: entry(.image, "снимок"))

        #expect(ActivityView.notesEntry(for: text, notesEnabled: true) != nil)
        #expect(ActivityView.notesEntry(for: text, notesEnabled: false) == nil)
        #expect(ActivityView.notesEntry(for: image, notesEnabled: true) == nil)
        #expect(ActivityView.notesEntry(for: .trackChanged, notesEnabled: true) == nil)

        #expect(ActivityView.sideButtonCount(text, notesEnabled: true) == 1)
        #expect(ActivityView.sideButtonCount(text, notesEnabled: false) == 0)
        // У полки крестик — и он же остаётся единственной боковой кнопкой.
        #expect(ActivityView.sideButtonCount(.shelf(count: 2), notesEnabled: true) == 1)
    }

    @Test("Плашка с кнопкой не уже плашки без неё")
    func плашкаСКнопкойШире() {
        // Длинный текст, чтобы плашка считалась по содержимому, а не упёрлась
        // в нижнюю границу ширины: на короткой разницы не увидеть.
        let kind = Activity.Kind.clipboard(entry: entry(.text, String(repeating: "слово ", count: 6)))
        let with = ActivityView.layout(for: kind, track: nil, metrics: metrics, notesEnabled: true)
        let without = ActivityView.layout(for: kind, track: nil, metrics: metrics, notesEnabled: false)
        #expect(with.panelWidth >= without.panelWidth)
        #expect(with.textWidth <= without.textWidth)
    }

    /// Выделенное в заметки сидит на той же букве, что и новая заметка,
    /// и разводит их ⇧. Совпасть они не имеют права: система отдаёт
    /// сочетание тому, кто успел зарегистрировать его первым.
    @Test("Сочетание выделенного не совпадает с прочими")
    func сочетаниеНеСовпадает() {
        var seen = Set<String>()
        let specs: [HotKeySpec] = [
            .assistant, .clipboard, .shelf, .timer, .monitor,
            .expanded, .teleprompter, .notes, .noteSelection,
        ]
        for spec in specs {
            #expect(seen.insert("\(spec.keyCode)-\(spec.modifiers)").inserted,
                    "сочетание \(spec.display) назначено дважды")
        }
        #expect(HotKeySpec.noteSelection.keyCode == HotKeySpec.notes.keyCode)
        #expect(!HotKeySpec.noteSelection.display.isEmpty)
    }
}
