import AppKit
import CoreAudio
import Foundation
import Testing
@testable import Trunook

/// Перебор звуковых устройств кнопкой в панели встречи.
///
/// Живой звуковой подсистемы в тестах нет, и она здесь не нужна: вся логика
/// кнопки — в одной чистой функции, а ошибиться в ней легко ровно на краях.
@Suite("Устройства звука")
struct AudioDevicesTests {
    private func device(_ uid: String, _ name: String) -> AudioDevice {
        AudioDevice(id: AudioDeviceID(abs(uid.hashValue % 1000)), uid: uid, name: name)
    }

    private var pair: [AudioDevice] {
        [device("a", "Динамики MacBook Pro"), device("b", "Наушники")]
    }

    @Test("Перебор идёт по кругу")
    func поКругу() {
        let devices = pair
        #expect(AudioDevices.next(after: devices[0], in: devices)?.uid == "b")
        #expect(AudioDevices.next(after: devices[1], in: devices)?.uid == "a")
    }

    /// Устройство одно — нажатие возвращает его же, а не пустоту: иначе
    /// кнопка молча ничего не делала бы, и это читалось бы как поломка.
    @Test("Одно устройство остаётся собой")
    func одноУстройство() {
        let only = [device("a", "Динамики MacBook Pro")]
        #expect(AudioDevices.next(after: only[0], in: only)?.uid == "a")
    }

    /// Наушники выдернули: нынешнего в списке больше нет. Берём первое —
    /// кнопку нажали, значит хотят сменить, и остаться ни с чем хуже всего.
    @Test("Пропавшее устройство уводит к первому")
    func пропавшееУстройство() {
        let devices = pair
        let gone = device("usb", "Внешняя карта")
        #expect(AudioDevices.next(after: gone, in: devices)?.uid == "a")
    }

    @Test("Нынешнего нет вовсе — берём первое")
    func безНынешнего() {
        #expect(AudioDevices.next(after: nil, in: pair)?.uid == "a")
    }

    @Test("Пустой список ничего не даёт")
    func пустойСписок() {
        #expect(AudioDevices.next(after: nil, in: []) == nil)
        #expect(AudioDevices.next(after: device("a", "Динамики"), in: []) == nil)
    }
}

/// Разбор ответа модели по расшифровке.
///
/// Живой модели в тесте нет, и она не нужна: разбор — чистая функция,
/// а отвечает модель каждый раз чуть иначе, и именно это здесь и ловится.
@Suite("Пересказ разговора")
struct TranscriptSummaryTests {
    @Test("Ровный ответ разбирается целиком")
    func ровныйОтвет() {
        let answer = """
            НАЗВАНИЕ: Планы на квартал
            ПЕРЕСКАЗ: Обсудили сроки и бюджет. Договорились начать в марте.
            ЗАДАЧИ:
            - Прислать смету
            - Согласовать сроки с подрядчиком
            """
        let parsed = TranscriptSummary.parse(answer)
        #expect(parsed?.title == "Планы на квартал")
        #expect(parsed?.summary.hasPrefix("Обсудили сроки") == true)
        #expect(parsed?.tasks == ["Прислать смету", "Согласовать сроки с подрядчиком"])
    }

    /// Модель любит обрамлять название кавычками и звёздочками разметки.
    @Test("Кавычки и разметка снимаются")
    func кавычки() {
        let parsed = TranscriptSummary.parse("""
            **НАЗВАНИЕ:** «Планы на квартал»
            ПЕРЕСКАЗ: Коротко обо всём.
            """)
        #expect(parsed?.title == "Планы на квартал")
    }

    /// `\r\n` — один символ, и резать надо только по `Character.isNewline`.
    /// Та же ловушка, что на описаниях выпусков и файлах хранилища.
    @Test("Чужие переносы строк не портят разбор")
    func чужиеПереносы() {
        let answer = "НАЗВАНИЕ: Созвон\r\nПЕРЕСКАЗ: Поговорили.\r\nЗАДАЧИ:\r\n- Позвонить\r\n"
        let parsed = TranscriptSummary.parse(answer)
        #expect(parsed?.title == "Созвон")
        #expect(parsed?.tasks == ["Позвонить"])
    }

    @Test("Нумерованный список тоже читается")
    func нумерованныйСписок() {
        let parsed = TranscriptSummary.parse("""
            ЗАДАЧИ:
            1. Прислать смету
            2. Позвонить в банк
            """)
        #expect(parsed?.tasks == ["Прислать смету", "Позвонить в банк"])
    }

    @Test("Чек-боксы модели не удваиваются в заметке")
    func чекБоксы() {
        let parsed = TranscriptSummary.parse("ЗАДАЧИ:\n- [ ] Прислать смету")
        #expect(parsed?.tasks == ["Прислать смету"])
    }

    @Test("«Нет» вместо задач даёт пустой список")
    func задачНет() {
        let parsed = TranscriptSummary.parse("ПЕРЕСКАЗ: Просто поболтали.\nЗАДАЧИ:\n- нет")
        #expect(parsed?.tasks.isEmpty == true)
        #expect(parsed?.summary == "Просто поболтали.")
    }

    /// Слово «задачи» посреди пересказа — не метка раздела. Иначе пересказ
    /// обрывался бы на середине, а его хвост уезжал в задачи.
    @Test("Слово «задачи» внутри пересказа меткой не считается")
    func словоВнутриПересказа() {
        let parsed = TranscriptSummary.parse("""
            ПЕРЕСКАЗ: Сначала обсудили бюджет.
            Задачи на квартал решили обсудить отдельно в конце месяца.
            """)
        #expect(parsed?.tasks.isEmpty == true)
        #expect(parsed?.summary.contains("Задачи на квартал") == true)
    }

    @Test("Ответ на английском разбирается так же")
    func английскийОтвет() {
        let parsed = TranscriptSummary.parse("""
            TITLE: Quarterly plans
            SUMMARY: We discussed the budget.
            TASKS:
            - Send the estimate
            """)
        #expect(parsed?.title == "Quarterly plans")
        #expect(parsed?.tasks == ["Send the estimate"])
    }

    /// Модель промолчала или ответила мимо формата — заметка соберётся
    /// из одной расшифровки, и это лучше выдуманного пересказа.
    @Test("Ответ мимо формата не даёт ничего")
    func мимоФормата() {
        #expect(TranscriptSummary.parse("Извините, я не могу это сделать.") == nil)
        #expect(TranscriptSummary.parse("") == nil)
    }

    /// Живой ответ модели: весь формат одним абзацем, без единого переноса.
    /// Так пришёл первый настоящий пересказ, и разбор по строкам увидел один
    /// сплошной пересказ, внутри которого лежали и метка, и обе задачи.
    @Test("Ответ одним абзацем разбирается на части")
    func ответОднимАбзацем() {
        let answer = "НАЗВАНИЕ: Покупки и парк ПЕРЕСКАЗ: Надо купить хлеб, "
            + "и нам нужно сходить в парк Челюскинцев. Нужно решить, что ещё купить. "
            + "ЗАДАЧИ - купить хлеб - сходить в парк Челюскинцев"
        let parsed = TranscriptSummary.parse(answer)

        #expect(parsed?.title == "Покупки и парк")
        #expect(parsed?.summary.hasPrefix("Надо купить хлеб") == true)
        // Главное: метка и задачи ушли из пересказа.
        #expect(parsed?.summary.contains("ЗАДАЧИ") == false)
        #expect(parsed?.tasks == ["купить хлеб", "сходить в парк Челюскинцев"])
    }

    /// Метка внутри строки перебивается переносом только если она настоящая:
    /// заглавными или с двоеточием. Обычное слово в пересказе — не метка.
    @Test("Обычное слово посреди абзаца меткой не становится")
    func обычноеСловоНеМетка() {
        let text = "ПЕРЕСКАЗ: Мы обсудили задачи на квартал и разошлись."
        let parsed = TranscriptSummary.parse(text)
        #expect(parsed?.summary == "Мы обсудили задачи на квартал и разошлись.")
        #expect(parsed?.tasks.isEmpty == true)
    }

    @Test("Заглавная метка без двоеточия тоже работает")
    func меткаБезДвоеточия() {
        let parsed = TranscriptSummary.parse("ЗАДАЧИ\n- позвонить")
        #expect(parsed?.tasks == ["позвонить"])
    }

    /// Модель повторяет вид метки из промта и отвечает заглавными.
    /// В списке заметок это кричит, а у записи уезжает ещё и в имя файла.
    @Test("Название, выкрикнутое заглавными, приводится к обычному виду")
    func названиеНеКричит() {
        let parsed = TranscriptSummary.parse("НАЗВАНИЕ: ХЛЕБ И ЧЕЛЮСКИНЦЫ")
        #expect(parsed?.title == "Хлеб и челюскинцы")
    }

    /// Короткое слово заглавными — аббревиатура, а не крик.
    @Test("Аббревиатуру не опускают")
    func аббревиатураЦела() {
        #expect(NoteTitler.deshouted("НДС") == "НДС")
        #expect(NoteTitler.deshouted("API") == "API")
        #expect(NoteTitler.deshouted("Планы на квартал") == "Планы на квартал")
    }

    // MARK: - Промты

    /// Первый живой пересказ аудиозаметки вышел так: «Мы решили купить хлеб.
    /// И договорились пойти в парк». Ни «мы», ни «договорились» в записи
    /// не было — человек наговорил себе список дел, а промт обещал модели
    /// «разговор», и она достроила собеседников.
    @Test("Аудиозаметке промт запрещает выдумывать собеседников")
    func промтЗаметкиБезСобеседников() {
        let prompt = TranscriptSummary.prompt(for: "Купить хлеб.", kind: .dictation)
        #expect(prompt.contains("сам себе"))
        #expect(prompt.contains("собеседников нет"))
        #expect(prompt.contains("Не пиши «мы»"))
    }

    @Test("У встречи промт остаётся про разговор")
    func промтВстречи() {
        let prompt = TranscriptSummary.prompt(for: "Обсудили сроки.", kind: .conversation)
        #expect(prompt.contains("расшифровка разговора"))
        #expect(prompt.contains("что обсудили"))
        #expect(!prompt.contains("собеседников нет"))
    }

    /// Оговорка нужна и при сведении длинной записи: второй заход к модели
    /// видит только пересказы кусков и без неё достроит то же самое.
    @Test("Сведение длинной записи не теряет оговорку")
    func сведениеСохраняетОговорку() {
        let merged = TranscriptSummary.mergePrompt(for: ["Часть один.", "Часть два."],
                                                   kind: .dictation)
        #expect(merged.contains("собеседников нет"))
    }

    // MARK: - Нарезка

    @Test("Короткая расшифровка остаётся одним куском")
    func короткаяРасшифровка() {
        #expect(TranscriptSummary.chunks(of: "Одна фраза.") == ["Одна фраза."])
        #expect(TranscriptSummary.chunks(of: "   ").isEmpty)
    }

    /// Резать надо по границам предложений: разрезанная посреди фразы
    /// мысль теряется в обеих половинах.
    @Test("Длинная режется по предложениям")
    func длиннаяРежется() {
        let sentence = "Это предложение ровно про одно. "
        let text = String(repeating: sentence, count: 20)
        let chunks = TranscriptSummary.chunks(of: text, limit: 100)

        #expect(chunks.count > 1)
        for chunk in chunks {
            #expect(chunk.hasSuffix("."))
        }
        // Ничего не потеряно: склеенные куски содержат все предложения.
        let joined = chunks.joined(separator: " ")
        #expect(joined.components(separatedBy: "ровно про одно").count - 1 == 20)
    }

    /// Предложение длиннее предела бывает у расшифровки без знаков
    /// препинания. Отдать его куском длиннее предела лучше, чем потерять.
    @Test("Слишком длинное предложение не теряется")
    func длинноеПредложение() {
        let text = String(repeating: "слово ", count: 100)
        let chunks = TranscriptSummary.chunks(of: text, limit: 50)
        #expect(chunks.count == 1)
        #expect(chunks[0].contains("слово"))
    }
}

/// Панель встречи после двух новых кнопок.
@Suite("Панель встречи")
struct MeetingPanelTests {
    /// Кнопок стало девять вместо шести, и ширина считается по ним же.
    /// Проверяется не число само по себе, а то, что расчёт учитывает все
    /// действия сразу: потолок ширины окна выреза стоит на `allCases`.
    @Test("Ширина растёт вместе с числом кнопок")
    func ширина() {
        let six = MeetingControlsView.width(actionCount: 6)
        let all = MeetingControlsView.width(actionCount: MeetingAction.allCases.count)
        #expect(MeetingAction.allCases.count == 9)
        #expect(all > six)
    }

    /// Своих кнопок три: две про устройства и запись. Их не ищут
    /// на странице, и встречей они не считаются — иначе главная страница
    /// сервиса без звонка выдавала бы себя за идущую встречу.
    @Test("Свои кнопки на странице не ищутся")
    func своиКнопки() {
        let own = MeetingAction.allCases.filter(\.isOwn)
        #expect(own == [.output, .input, .record])
        for action in own {
            #expect(action.labels.isEmpty)
        }
        #expect(!MeetingAction.copyLink.isOwn)
    }

    /// У записи значок меняется: точка — начать, квадрат — закончить.
    /// Это единственная кнопка в ряду, где состояние говорит
    /// о самом приложении, а не о встрече.
    @Test("Значок записи меняется вместе с состоянием")
    func значокЗаписи() {
        #expect(MeetingAction.record.symbol(isOn: true)
            != MeetingAction.record.symbol(isOn: false))
    }

    /// Устройства звука не ищутся на странице встречи, поэтому подписей
    /// кнопок у них быть не должно: непустой список означал бы, что обход
    /// начнёт искать их среди кнопок браузера.
    @Test("У кнопок устройств нет подписей для поиска на странице")
    func устройстваНеИщутся() {
        for action in MeetingAction.allCases where action.isDevice {
            #expect(action.labels.isEmpty)
        }
        #expect(MeetingAction.output.isDevice)
        #expect(MeetingAction.input.isDevice)
        #expect(!MeetingAction.microphone.isDevice)
    }

    /// Значок у кнопки устройства один и тот же: состояния «включено» у неё
    /// нет, и мигать значком было бы враньём.
    @Test("Значок устройства не зависит от состояния")
    func значокПостоянный() {
        for action in MeetingAction.allCases where action.isDevice {
            #expect(action.symbol(isOn: true) == action.symbol(isOn: false))
        }
    }
}

/// Полоска записи в свёрнутом вырезе.
@Suite("Полоска записи")
struct RecordingChipTests {
    private let recording = RecordingChip(isRecording: true, showsHours: false)
    private let timer = TimerChip(symbol: "timer", showsHours: false)
    private let metrics = NotchMetrics(notchWidth: 185, notchHeight: 32)

    @Test("Одна запись превращает свёрнутый вырез в полоску")
    func полоскаПоявляется() {
        #expect(NotchInputs().resolve().presentation == .collapsed)
        #expect(NotchInputs(recordingChip: recording).resolve().presentation == .chip)
    }

    /// Запись легко забыть выключенной, и цена этому — час звука мимо
    /// заметки. Пропущенный таймер стоит одного взгляда на часы, поэтому
    /// запись и стоит выше.
    @Test("Запись занимает вырез раньше таймера")
    func записьВажнееТаймера() {
        let both = NotchInputs(recordingChip: recording, timerChip: timer)
        let size = NotchSizing.size(
            presentation: both.resolve().presentation,
            content: both.resolve().content,
            metrics: metrics
        )
        let onlyRecording = NotchInputs(recordingChip: recording)
        let expected = NotchSizing.size(
            presentation: .chip,
            content: onlyRecording.resolve().content,
            metrics: metrics
        )
        #expect(size == expected)
    }

    /// Накладка важнее любой полоски: её открыли руками прямо сейчас.
    @Test("Открытая накладка перебивает полоску записи")
    func накладкаВажнее() {
        let inputs = NotchInputs(overlay: .notes, recordingChip: recording)
        #expect(inputs.resolve().presentation == .notes)
    }

    /// Часы появляются только у длинной записи: полоска, меняющая ширину
    /// каждую секунду, дёргала бы остров.
    @Test("Часы расширяют полоску, минуты — нет")
    func часыШире() {
        let short = RecorderChipView.width(metrics: metrics, showsHours: false)
        let long = RecorderChipView.width(metrics: metrics, showsHours: true)
        #expect(long > short)
    }
}

/// Запись в файле хранилища.
///
/// Ссылка на аудио живёт блоком между невидимыми метками — как связи,
/// и по той же причине: `![[запись.m4a]]` посреди текста заметки это
/// приписка, которую человек не писал. Первая версия ставила её прямо
/// в текст, и в вырезе она так и выглядела — голой разметкой.
@Suite("Блок записи в файле")
struct RecordingBlockTests {
    private let path = "Trunook/Recordings/2026-09-06-0906.m4a"

    @Test("Блок встаёт перед текстом, а не после")
    func блокВпереди() {
        let file = ObsidianMarkdown.settingAudio(path, in: "Пересказ встречи.")
        let lines = file.split(separator: "\n").map(String.init)
        #expect(lines.first == ObsidianMarkdown.audioStart)
        #expect(file.contains("![[" + path + "]]"))
        // Проигрыватель под расшифровкой на тысячу строк человек не найдёт.
        #expect(file.hasSuffix("Пересказ встречи."))
    }

    @Test("Повторная запись заменяет прежний блок, а не множит его")
    func блокНеМножится() {
        let once = ObsidianMarkdown.settingAudio(path, in: "Текст.")
        let twice = ObsidianMarkdown.settingAudio("Trunook/Recordings/новая.m4a", in: once)
        #expect(twice.components(separatedBy: ObsidianMarkdown.audioStart).count - 1 == 1)
        #expect(!twice.contains(path))
        #expect(twice.contains("новая.m4a"))
    }

    @Test("Пустой путь снимает блок целиком")
    func пустойПутьСнимает() {
        let once = ObsidianMarkdown.settingAudio(path, in: "Текст.")
        #expect(ObsidianMarkdown.settingAudio(nil, in: once) == "Текст.")
    }

    /// Главное: блок не должен вернуться в текст заметки при чтении файла
    /// обратно. Иначе на каждой сверке заметка обрастала бы копией ссылки.
    @Test("Чтение файла не тащит блок записи в заметку")
    func кругНеТащитБлок() {
        let body = ObsidianMarkdown.settingAudio(path, in: "Пересказ встречи.")
        let file = "---\ntrunook: 1\n---\n\n" + body
        #expect(ObsidianMarkdown.readableBody(of: file) == "Пересказ встречи.")
    }

    /// Связи и запись стоят в одном файле и не мешают друг другу: запись
    /// сверху, связи снизу, текст между ними.
    @Test("Запись и связи уживаются в одном файле")
    func записьИСвязи() {
        var body = ObsidianMarkdown.settingAudio(path, in: "Пересказ встречи.")
        body = ObsidianMarkdown.settingLinks(
            ObsidianMarkdown.linksBlock(lines: ["- [[Другая]] — про одно"]), in: body
        )
        #expect(body.contains(path))
        #expect(body.contains("[[Другая]]"))
        #expect(ObsidianMarkdown.readableBody(of: body) == "Пересказ встречи.")
    }

    /// В самой заметке ссылки нет вовсе — только пересказ, задачи
    /// и расшифровка.
    @Test("Текст заметки не содержит разметки ссылки")
    func заметкаБезРазметки() {
        let summary = RecordingSummary(
            title: "Планы", summary: "Обсудили сроки.", tasks: ["Прислать смету"]
        )
        let text = RecordingNote.text(summary: summary, transcript: "Здравствуйте.").string
        #expect(!text.contains("![["))
        #expect(text.contains("Обсудили сроки."))
        #expect(text.contains("- [ ] Прислать смету"))
        #expect(text.contains("Здравствуйте."))
    }

    /// Заголовки задаются кеглем: по нему `NoteMarkdown` и опознаёт
    /// заголовок при выгрузке в файл. Набранные обычным кеглем, они уехали
    /// бы в `.md` простым текстом, а в вырезе слились бы с абзацем.
    @Test("Заголовки разделов набраны заголовочным кеглем")
    func заголовкиКеглем() {
        let summary = RecordingSummary(title: nil, summary: "Итог.", tasks: ["Дело"])
        let text = RecordingNote.text(summary: summary, transcript: "Слова.")
        let string = text.string as NSString

        for heading in [t("Задачи"), t("Расшифровка")] {
            let range = string.range(of: heading)
            #expect(range.location != NSNotFound)
            let font = text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            #expect(font?.pointSize == Note.headingFontSize)
        }

        // А сам текст — обычным.
        let body = string.range(of: "Итог.")
        let font = text.attribute(.font, at: body.location, effectiveRange: nil) as? NSFont
        #expect(font?.pointSize == Note.bodyFontSize)
    }

    /// Модель промолчала — заметка всё равно собирается из расшифровки.
    @Test("Без пересказа остаётся расшифровка")
    func безПересказа() {
        let text = RecordingNote.text(summary: nil, transcript: "Здравствуйте.").string
        #expect(text.contains("Здравствуйте."))
    }
}

/// Открытая заметка: правили её или нет.
///
/// Признак решает, что написано на главной кнопке панели — «Сохранить»
/// или «Закрыть», — и потому проверяется отдельно. Живого поля ввода
/// в тестах нет, и оно здесь не нужно: пока поле не построено, текст ждёт
/// в черновике, и сверка идёт по нему.
@Suite("Правка заметки")
struct NoteDraftEditingTests {
    private func note(_ text: String) -> Note {
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: Note.bodyFontSize),
            .foregroundColor: NSColor.white,
        ])
        return Note(
            id: 7,
            title: "Заметка",
            rtf: attributed.rtf(from: NSRange(location: 0, length: attributed.length),
                                documentAttributes: [:]) ?? Data(),
            plain: text,
            createdAt: Date(),
            updatedAt: Date(),
            origin: .typed,
            titleByModel: false
        )
    }

    @MainActor
    @Test("Только что открытая заметка правкой не считается")
    func открытаяНеПравлена() {
        let draft = NoteDraft()
        draft.load(note("Купить хлеб"))
        #expect(draft.editingID == 7)
        #expect(draft.isNoteEdited == false)
    }

    /// Закрыли правку — признак снимается вместе с привязкой к записи.
    /// Иначе следующая заметка открылась бы сразу «правленой».
    @MainActor
    @Test("Закрытие правки снимает признак")
    func закрытиеСнимаетПризнак() {
        let draft = NoteDraft()
        draft.load(note("Купить хлеб"))
        draft.clearNote()
        #expect(draft.editingID == nil)
        #expect(draft.isNoteEdited == false)
    }

    @MainActor
    @Test("Уход из панели тоже снимает правку")
    func уходСнимаетПравку() {
        let draft = NoteDraft()
        draft.load(note("Купить хлеб"))
        draft.endEditing()
        #expect(draft.editingID == nil)
        #expect(draft.isNoteEdited == false)
    }

    /// Новая заметка поверх открытой не должна тащить за собой чужую правку.
    @MainActor
    @Test("Новая заметка начинается нетронутой")
    func новаяНетронута() {
        let draft = NoteDraft()
        draft.load(note("Купить хлеб"))
        draft.startNewNote()
        #expect(draft.editingID == nil)
        #expect(draft.isNoteEdited == false)
    }
}
