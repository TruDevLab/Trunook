import TrunookXPC
import Foundation

/// Команда — строка в списке под полем вопроса.
///
/// Была слотом меню, одним из шести. Слотов больше нет: команд заводят
/// сколько нужно и переставляют, а порядок задаётся местом в наборе.
struct QuickCommand: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, CaseIterable {
        case shortcut
        case ollama
        case openApp
        case openPath
        case openURL
        case appleScript
        /// Захваченный текст сразу в заметки. Ни промта, ни модели: это
        /// то же, что делает ⌃⌥⇧Z, только из списка команд.
        case saveToNotes

        var title: String {
            switch self {
            case .shortcut: return t("Команда из «Команд»")
            case .ollama: return t("Запрос к модели")
            case .openApp: return t("Открыть приложение")
            case .openPath: return t("Открыть файл или папку")
            case .openURL: return t("Открыть ссылку")
            case .appleScript: return t("Скрипт AppleScript")
            case .saveToNotes: return t("Сохранить в заметки")
            }
        }

        var defaultSymbol: String {
            switch self {
            case .shortcut: return "square.stack.3d.up.fill"
            case .ollama: return "sparkles"
            case .openApp: return "app.badge"
            case .openPath: return "folder"
            case .openURL: return "link"
            case .appleScript: return "applescript"
            case .saveToNotes: return "tray.and.arrow.down"
            }
        }

        /// Уходит ли команда к модели. От этого зависит, показывать ли
        /// в её строке имя модели и давать ли его менять.
        var usesModel: Bool { self == .ollama }

        /// Есть ли у команды содержимое, которое нужно заполнить. У записи
        /// в заметки его нет вовсе: она работает с захваченным текстом,
        /// а не со своим промтом, — и требовать от неё непустой `payload`
        /// значило бы навсегда оставить её ненастроенной.
        var needsPayload: Bool { self != .saveToNotes }
    }

    /// Постоянный номер команды. Не её место в списке: место задаётся
    /// порядком в наборе и меняется перестановкой, а номер остаётся при
    /// команде навсегда — по нему её находят настройки и горячая клавиша.
    let id: Int
    var title: String
    var kind: Kind
    /// Промт, текст скрипта, путь к приложению или путь к папке.
    var payload: String
    var symbol: String
    var isEnabled: Bool
    /// Своё сочетание. nil — команда запускается только из списка.
    var hotKey: HotKeySpec?
    /// Передавать ли выделенный текст на вход. Для команд из «Команд»:
    /// многие из них работают с текстом, а многие — сами по себе.
    var passesSelection: Bool = false
    /// В каком браузере открывать ссылку. `nil` — в браузере по умолчанию.
    ///
    /// Необязательное поле намеренно: у синтезированного `Decodable`
    /// значения по умолчанию не работают, а вот отсутствующий ключ
    /// необязательного свойства читается как `nil`. Иначе слоты, сохранённые
    /// прошлой версией, перестали бы разбираться целиком.
    var browserBundleID: String?

    /// Какой моделью выполнять. `nil` — той, что выбрана в настройках.
    ///
    /// У каждой команды своя: переводу хватает лёгкой модели, разбору кода
    /// нужна тяжёлая, и одна на всё приложение заставляла бы переключать её
    /// руками между двумя соседними вопросами.
    ///
    /// Необязательное поле намеренно — по той же причине, что
    /// и `browserBundleID`: у синтезированного `Decodable` значения
    /// по умолчанию не работают, а отсутствующий ключ необязательного
    /// свойства читается как `nil`. Иначе наборы, сохранённые прошлой
    /// версией, перестали бы разбираться целиком.
    var model: String?

    /// Новая команда: заготовка, которую человек тут же и заполнит.
    static func blank(id: Int) -> QuickCommand {
        QuickCommand(
            id: id,
            title: "",
            kind: .ollama,
            payload: "",
            symbol: "",
            isEnabled: true,
            hotKey: nil
        )
    }

    var isConfigured: Bool {
        guard isEnabled, !title.isEmpty else { return false }
        return !kind.needsPayload || !payload.isEmpty
    }

    var effectiveSymbol: String {
        symbol.isEmpty ? kind.defaultSymbol : symbol
    }

    /// Подстановка выделенного текста в промт.
    ///
    /// Если места подстановки нет, текст дописывается снизу: иначе команда,
    /// заданная одной фразой вроде «переведи на английский», молча теряла бы
    /// то, к чему её применяют.
    /// Разбирает ссылку из того, что вписал человек.
    ///
    /// Схему дописываем сами: адрес обычно копируют или набирают без неё,
    /// а `NSWorkspace` без схемы такую строку не откроет.
    static func webURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        return URL(string: "https://" + trimmed)
    }

    func prompt(with selection: String) -> String {
        let marker = "{{selection}}"
        guard payload.contains(marker) else {
            return selection.isEmpty ? payload : "\(payload)\n\n\(selection)"
        }
        return payload.replacingOccurrences(of: marker, with: selection)
    }
}

/// Набор команд: сколько угодно, в том порядке, в каком их расставили.
///
/// Слотов было шесть, и число было фиксировано нарочно — меню вызывалось
/// вслепую, по памяти, и растущий список сводил бы на нет саму идею. Меню
/// больше нет: команды показываются списком в панели, где их читают глазами,
/// и ограничивать их число стало незачем.
enum QuickCommands {
    /// Сколько строк списка видно разом. Дальше — прокрутка: список, который
    /// может пополниться, обязан быть прокручиваемым, иначе он однажды
    /// перерастёт окно и обрежется с обеих сторон.
    static let visibleRows = 4

    static func load(from defaults: UserDefaults) -> [QuickCommand] {
        guard let data = defaults.data(forKey: "quickCommands"),
              let stored = try? JSONDecoder().decode([QuickCommand].self, from: data)
        else { return defaults0 }

        // Порядок — тот, в каком команды лежат в наборе. Приведение
        // к шести слотам ушло вместе со слотами; пустышки старого формата,
        // заводившиеся под ненастроенные места меню, выбрасываются:
        // показывать их в списке не за чем, а редактировать — тем более.
        var commands = stored.filter { !$0.title.isEmpty || !$0.payload.isEmpty }
        var changed = migrateLegacyHotKeys(&commands, in: defaults)
        changed = addNoteCommand(&commands, in: defaults) || changed
        changed = nameProviderOfModels(&commands, in: defaults) || changed
        if changed { save(commands, to: defaults) }
        return commands
    }

    static let modelProviderKey = "quickCommandModelsGotProvider"

    /// Дописывает к имени модели того, кто её отдаёт.
    ///
    /// Пока провайдер был один, имени хватало. Теперь их держат несколько,
    /// и голое имя молча означало бы «у основного» — а основного меняют,
    /// и команда, настроенная на местную модель, однажды ушла бы в облако.
    ///
    /// Переносим один раз, к тому провайдеру, который на момент переноса
    /// и был единственным.
    private static func nameProviderOfModels(
        _ commands: inout [QuickCommand],
        in defaults: UserDefaults
    ) -> Bool {
        guard !(defaults.object(forKey: modelProviderKey) as? Bool ?? false) else { return false }
        defaults.set(true, forKey: modelProviderKey)

        let owner = AIProvider(rawValue: defaults.string(forKey: "aiProvider") ?? "") ?? .ollama
        var changed = false
        for index in commands.indices {
            guard let stored = commands[index].model, !stored.isEmpty,
                  let ref = ModelRef.parse(stored, fallback: owner), ref.stored != stored
            else { continue }
            commands[index].model = ref.stored
            changed = true
        }
        if changed { DebugLog.write("команды: к именам моделей дописан провайдер \(owner.rawValue)") }
        return changed
    }

    /// Ключ, которым помечена состоявшаяся выдача команды «в заметки».
    ///
    /// Не `private`: его ставит проверка, которой перенос мешает. Выписанный
    /// в тесте строкой, он разошёлся бы с этим при первом переименовании,
    /// и перенос молча начал бы срабатывать в каждой проверке.
    static let noteCommandKey = "quickCommandsGotNoteCommand"

    /// Дописывает «Сохранить в заметки» тем, у кого набор уже есть.
    ///
    /// Заготовки первого запуска до этих людей не доходят: их набор лежит
    /// в настройках с прошлой версии, и новая команда не появилась бы у них
    /// никогда — притом что руками её не собрать, вида `saveToNotes` в старом
    /// списке действий просто не было.
    ///
    /// Отметка нужна, чтобы выдача случилась однажды: без неё команда
    /// возвращалась бы на место при каждом запуске у всех, кто нарочно
    /// её удалил.
    private static func addNoteCommand(
        _ commands: inout [QuickCommand],
        in defaults: UserDefaults
    ) -> Bool {
        guard !defaults.bool(forKey: noteCommandKey) else { return false }
        defaults.set(true, forKey: noteCommandKey)

        guard !commands.contains(where: { $0.kind == .saveToNotes }) else { return false }
        commands.append(QuickCommand(
            id: nextID(after: commands),
            title: t("Сохранить в заметки"),
            kind: .saveToNotes,
            payload: "",
            symbol: "tray.and.arrow.down",
            isEnabled: true,
            // Без сочетания: свободные цифры у человека могли кончиться,
            // а отобрать занятую значило бы молча переназначить то, чем он
            // уже пользуется.
            hotKey: nil
        ))
        return true
    }

    /// Что показывает список под полем вопроса.
    ///
    /// Один расчёт на всех: список рисует вёрстка, а ходит по нему стрелками
    /// контроллер — и «третья сверху» у них обязана означать одно и то же.
    /// Порознь эти два списка разошлись бы на первой же выключенной команде,
    /// и стрелка вела бы подсветку мимо видимых строк.
    /// `modelEnabled` — включена ли Ollama. Выключена — команды к модели
    /// из списка уходят: показывать то, что заведомо ответит «Ollama выключена
    /// в настройках», значит предлагать нажать и получить отказ. Остальные
    /// виды работают без всякой модели, и отбирать их заодно не за что.
    static func visible(
        in commands: [QuickCommand],
        enabled: Bool,
        modelEnabled: Bool
    ) -> [QuickCommand] {
        guard enabled else { return [] }
        return commands.filter { $0.isConfigured && (modelEnabled || !$0.kind.usesModel) }
    }

    /// Номер для новой команды: на единицу больше самого большого занятого.
    ///
    /// Не число команд: удалили среднюю — и новая получила бы номер уже
    /// существующей, а по номеру команду находят и настройки, и клавиша.
    static func nextID(after commands: [QuickCommand]) -> Int {
        (commands.map(\.id).max() ?? -1) + 1
    }

    /// Ключ, которым помечен состоявшийся перенос сочетаний.
    private static let migrationKey = "quickCommandHotKeysMigrated"

    /// Переносит нетронутые сочетания слотов с ⌥⌘ на ⌃⌥.
    ///
    /// До 0.6.0 слоты сидели на ⌥⌘ с цифрами, остальное приложение — на ⌃⌥.
    /// Сменить умолчание оказалось мало: у всех, кто уже запускал приложение,
    /// набор лежит в настройках со старыми сочетаниями, и меню функций честно
    /// показывало ⌥⌘1, пока рядом стояли ⌃⌥C и ⌃⌥V. Выглядело это как
    /// недоделка, а не как чужой выбор.
    ///
    /// Переносится только то, чего человек не касался: сочетание, совпадающее
    /// со старым умолчанием **своего** слота. Заданное вручную остаётся как
    /// есть. Отметка в настройках нужна, чтобы перенос случился однажды —
    /// иначе он молча переписывал бы выбор того, кто нарочно вернул ⌥⌘1.
    private static func migrateLegacyHotKeys(
        _ commands: inout [QuickCommand],
        in defaults: UserDefaults
    ) -> Bool {
        guard !defaults.bool(forKey: migrationKey) else { return false }
        defaults.set(true, forKey: migrationKey)

        var changed = false
        for index in commands.indices {
            let command = commands[index]
            guard let hotKey = command.hotKey,
                  hotKey == HotKeySpec.legacySlot(command.id),
                  let fresh = HotKeySpec.slot(command.id)
            else { continue }
            commands[index].hotKey = fresh
            changed = true
        }
        return changed
    }

    static func save(_ commands: [QuickCommand], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(commands) else { return }
        defaults.set(data, forKey: "quickCommands")
    }

    /// Заготовки при первом запуске: показывают, что вообще умеет список.
    private static var defaults0: [QuickCommand] {
        [
            QuickCommand(
                id: 0,
                title: t("Исправить ошибки"),
                kind: .ollama,
                payload: t("Исправь орфографию и пунктуацию. Верни только исправленный текст, без пояснений.\n\n{{selection}}"),
                symbol: "text.badge.checkmark",
                isEnabled: true,
                hotKey: HotKeySpec.slot(0)
            ),
            QuickCommand(
                id: 1,
                title: t("Перевести на русский"),
                kind: .ollama,
                payload: t("Переведи на русский. Верни только перевод.\n\n{{selection}}"),
                symbol: "character.book.closed",
                isEnabled: true,
                hotKey: HotKeySpec.slot(1)
            ),
            QuickCommand(
                id: 2,
                title: t("Кратко пересказать"),
                kind: .ollama,
                payload: t("Перескажи кратко, тремя пунктами.\n\n{{selection}}"),
                symbol: "list.bullet.rectangle",
                isEnabled: true,
                hotKey: HotKeySpec.slot(2)
            ),
            // Записать захваченное, ничего не спрашивая у модели. Идёт
            // из коробки, но ничем не особеннее прочих: её можно удалить,
            // переставить и переименовать.
            QuickCommand(
                id: 3,
                title: t("Сохранить в заметки"),
                kind: .saveToNotes,
                payload: "",
                symbol: "tray.and.arrow.down",
                isEnabled: true,
                hotKey: HotKeySpec.slot(3)
            ),
        ]
    }
}
