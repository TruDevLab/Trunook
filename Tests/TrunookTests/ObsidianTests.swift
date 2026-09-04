import AppKit
import Foundation
import Testing
@testable import Trunook

/// Хранилище как значение: правила обхода, места, ссылка в Obsidian.
///
/// Настоящего хранилища человека тесты не касаются вовсе — дерево собирается
/// во временной папке. Это то же правило, по которому `NotesStore` принимает
/// путь в `init`: проверка не имеет права трогать чужие данные.
@Suite("Хранилище Obsidian")
struct VaultTests {
    // MARK: - Правила обхода

    @Test("Служебные папки Obsidian в обход не идут")
    func служебноеПропускается() {
        #expect(Vault.isSkipped(relativePath: ".obsidian/app.json"))
        #expect(Vault.isSkipped(relativePath: ".trash/Заметка.md"))
        #expect(Vault.isSkipped(relativePath: "Проекты/.git/config"))
        #expect(Vault.isSkipped(relativePath: ""))
    }

    /// Недокачанная заглушка iCloud называется `.Имя.md.icloud` — она
    /// начинается с точки, и то же правило снимает её даром.
    @Test("Заглушка iCloud не принимается за заметку")
    func заглушкаICloudПропускается() {
        #expect(Vault.isSkipped(relativePath: "Проекты/.Роадмап.md.icloud"))
    }

    @Test("Обычная заметка проходит")
    func обычнаяПроходит() {
        #expect(!Vault.isSkipped(relativePath: "Проекты/Роадмап.md"))
        #expect(!Vault.isSkipped(relativePath: "Заметка.md"))
    }

    @Test("Заметка — только .md, регистр не важен")
    func толькоMarkdown() {
        #expect(Vault.isNote("Роадмап.md"))
        #expect(Vault.isNote("Роадмап.MD"))
        #expect(!Vault.isNote("схема.png"))
        #expect(!Vault.isNote("доска.canvas"))
        #expect(!Vault.isNote(".md"), "файл без имени заметкой не считается")
    }

    // MARK: - Места

    @Test("Пустое имя подпапки не отправляет запись в корень хранилища")
    func пустаяПодпапкаПодменяется() {
        let vault = Vault(url: URL(fileURLWithPath: "/tmp/vault"), folder: "   ")
        #expect(vault.folder == Vault.defaultFolder)
    }

    @Test("Пустой путь хранилищем не становится")
    func пустойПутьНеХранилище() {
        #expect(Vault(path: "") == nil)
        #expect(Vault(path: "   ") == nil)
    }

    @Test("Тильда в пути раскрывается")
    func тильдаРаскрывается() throws {
        let vault = try #require(Vault(path: "~/Заметки"))
        #expect(!vault.url.path.contains("~"))
        #expect(vault.url.path.hasSuffix("/Заметки"))
    }

    @Test("Своё отличается от чужого по подпапке")
    func своёОтличаетсяОтЧужого() {
        let vault = Vault(url: URL(fileURLWithPath: "/tmp/vault"), folder: "Trunook")
        #expect(vault.isOwn("Trunook/Идея.md"))
        #expect(!vault.isOwn("Проекты/Роадмап.md"))
        #expect(!vault.isOwn("TrunookДругое/Идея.md"), "совпадение начала имени — не своя папка")
    }

    @Test("Имя хранилища — имя его папки")
    func имяХранилища() {
        let vault = Vault(url: URL(fileURLWithPath: "/Users/кто-то/Documents/Мысли"))
        #expect(vault.name == "Мысли")
    }

    // MARK: - Ссылка в Obsidian

    @Test("Ссылка снимает расширение и уводит косую в проценты")
    func ссылкаВObsidian() throws {
        let vault = Vault(url: URL(fileURLWithPath: "/tmp/Мысли"))
        let url = try #require(vault.openURL(for: "Проекты/Роадмап.md"))
        let text = url.absoluteString
        #expect(text.hasPrefix("obsidian://open?vault="))
        #expect(!text.contains(".md"), "в схеме file — имя заметки, а не имя файла")
        #expect(!text.contains("/Роадмап"), "косая обязана уйти в проценты")
        #expect(text.contains("%2F"))
    }

    // MARK: - Снимок файла

    @Test("Имя заметки — имя файла без расширения")
    func имяЗаметки() {
        let file = VaultFile(path: "Проекты/Роадмап.md", modified: Date(), size: 10)
        #expect(file.title == "Роадмап")
    }

    @Test("Расширение снимается только с хвоста")
    func расширениеТолькоСХвоста() {
        let file = VaultFile(path: "Заметки.md о работе.md", modified: Date(), size: 10)
        #expect(file.title == "Заметки.md о работе")
    }

    @Test("Отпечаток ловит правку и не ловит её отсутствие")
    func отпечаток() {
        let one = VaultFile.hash(of: "# Заголовок\n\nтекст")
        #expect(one == VaultFile.hash(of: "# Заголовок\n\nтекст"))
        #expect(one != VaultFile.hash(of: "# Заголовок\n\nтекст."))
        #expect(one.count == 64, "SHA-256 шестнадцатеричным — 64 знака")
    }
}

/// Обход настоящего дерева во временной папке.
@Suite("Обход хранилища")
struct VaultScannerTests {
    // MARK: - Обвязка

    private func makeVault() throws -> Vault {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("trunook-vault-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Хранилище опознаётся по этой папке — заводим, чтобы дерево было
        // похоже на настоящее.
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".obsidian"),
            withIntermediateDirectories: true
        )
        return Vault(url: root)
    }

    private func remove(_ vault: Vault) {
        try? FileManager.default.removeItem(at: vault.url)
    }

    @discardableResult
    private func put(_ text: String, at path: String, in vault: Vault) throws -> URL {
        let url = vault.fileURL(for: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Тесты

    @Test("Обход собирает заметки и пропускает всё прочее")
    func обходСобираетТолькоЗаметки() throws {
        let vault = try makeVault()
        defer { remove(vault) }

        try put("своя", at: "Trunook/Идея.md", in: vault)
        try put("чужая", at: "Проекты/Роадмап.md", in: vault)
        try put("глубже", at: "Проекты/2026/Планы.md", in: vault)
        try put("не заметка", at: "Проекты/схема.png", in: vault)
        try put("служебное", at: ".obsidian/app.json", in: vault)
        try put("в корзине", at: ".trash/Старое.md", in: vault)

        let paths = Set(VaultScanner.files(in: vault).map(\.path))
        #expect(paths == ["Trunook/Идея.md", "Проекты/Роадмап.md", "Проекты/2026/Планы.md"])
    }

    @Test("Слишком крупный файл не читается")
    func крупныйПропускается() throws {
        let vault = try makeVault()
        defer { remove(vault) }

        try put(String(repeating: "а", count: Vault.maxFileBytes), at: "Свалка.md", in: vault)
        try put("короткая", at: "Заметка.md", in: vault)

        let paths = VaultScanner.files(in: vault).map(\.path)
        #expect(paths == ["Заметка.md"])
    }

    @Test("Обход подпапки не выходит за неё")
    func обходПодпапки() throws {
        let vault = try makeVault()
        defer { remove(vault) }

        try put("своя", at: "Trunook/Идея.md", in: vault)
        try put("чужая", at: "Проекты/Роадмап.md", in: vault)

        let paths = VaultScanner.ownFiles(in: vault).map(\.path)
        #expect(paths == ["Trunook/Идея.md"], "путь остаётся от корня хранилища, а не от подпапки")
    }

    /// Главная защита всей работы: недоступная папка не имеет права выглядеть
    /// как пустое хранилище. Здесь проверяется только половина правила —
    /// что обход честно говорит «смотреть негде»; вторая половина, отказ
    /// сверки что-либо делать, живёт в `SyncPlan`.
    @Test("Пропавшая папка не выглядит пустым хранилищем")
    func пропавшаяПапка() {
        let vault = Vault(url: URL(fileURLWithPath: "/tmp/нет-такой-папки-\(UUID().uuidString)"))
        #expect(!vault.isReachable)
        #expect(VaultScanner.files(in: vault).isEmpty)
    }

    @Test("Папка без .obsidian хранилищем не притворяется")
    func непохожаяПапка() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("trunook-plain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let vault = Vault(url: root)
        #expect(vault.isReachable, "папка на месте")
        #expect(!vault.looksLikeVault, "но хранилищем Obsidian её называть не за что")
    }

    @Test("Дата правки и размер доезжают из файловой системы")
    func датаИРазмер() throws {
        let vault = try makeVault()
        defer { remove(vault) }

        let url = try put("текст", at: "Заметка.md", in: vault)
        let stamp = Date(timeIntervalSince1970: 1_757_000_000)
        try FileManager.default.setAttributes([.modificationDate: stamp], ofItemAtPath: url.path)

        let file = try #require(VaultScanner.files(in: vault).first)
        #expect(abs(file.modified.timeIntervalSince(stamp)) < 1)
        #expect(file.size == "текст".utf8.count)
    }

    @Test("Запись заводит недостающие папки, чтение возвращает то же")
    func записьИЧтение() throws {
        let vault = try makeVault()
        defer { remove(vault) }

        let text = "# Заголовок\n\nтекст заметки\n"
        #expect(VaultScanner.write(text, to: "Trunook/Глубже/Идея.md", in: vault))
        #expect(VaultScanner.text(at: "Trunook/Глубже/Идея.md", in: vault) == text)
    }

    @Test("Файл не в UTF-8 читается как ничто, а не как каша")
    func чужаяКодировка() throws {
        let vault = try makeVault()
        defer { remove(vault) }

        let data = try #require("Привет".data(using: .windowsCP1251))
        try data.write(to: vault.fileURL(for: "Чужое.md"))
        #expect(VaultScanner.text(at: "Чужое.md", in: vault) == nil)
    }

    @Test("Удаление уносит в Корзину, а не мимо неё")
    func удалениеВКорзину() throws {
        let vault = try makeVault()
        defer { remove(vault) }

        try put("прощай", at: "Ненужное.md", in: vault)
        let moved = try #require(VaultScanner.trash("Ненужное.md", in: vault), "файл обязан доехать до Корзины")
        // Убираем за собой: иначе каждый прогон тестов оставлял бы
        // человеку по файлу в Корзине.
        defer { try? FileManager.default.removeItem(at: moved) }

        #expect(!FileManager.default.fileExists(atPath: vault.fileURL(for: "Ненужное.md").path))
        #expect(FileManager.default.fileExists(atPath: moved.path), "и остаться там целым")
    }

    @Test("Занятое имя разводится суффиксом")
    func свободноеИмя() throws {
        let vault = try makeVault()
        defer { remove(vault) }

        try put("первая", at: "Trunook/2026-09-04-Идея.md", in: vault)
        let free = VaultScanner.freePath(fileName: "2026-09-04-Идея.md", in: vault, taken: [])
        #expect(free == "Trunook/2026-09-04-Идея-2.md")
    }

    @Test("Занятое в этом же заходе имя тоже считается занятым")
    func занятоеВЭтомЗаходе() throws {
        let vault = try makeVault()
        defer { remove(vault) }

        let taken: Set<String> = ["Trunook/Идея.md"]
        let free = VaultScanner.freePath(fileName: "Идея.md", in: vault, taken: taken)
        #expect(free == "Trunook/Идея-2.md", "на диске файла ещё нет, но имя уже роздано")
    }
}

/// Файл хранилища: шапка свойств, блок связей, круг «файл → заметка → файл».
@Suite("Файл хранилища")
struct ObsidianMarkdownTests {
    // MARK: - Шапка свойств

    @Test("Шапка отделяется от тела")
    func шапкаОтделяется() {
        let text = "---\ntrunook: 123\ncreated: 2026-09-04T14:20:11Z\n---\n\nтело\n"
        let parts = ObsidianMarkdown.split(text)
        #expect(parts.front == ["trunook: 123", "created: 2026-09-04T14:20:11Z"])
        #expect(parts.body == "тело\n")
    }

    /// `---` посреди текста — горизонтальная черта. Принять её за начало
    /// свойств значило бы съесть половину заметки.
    @Test("Черта посреди текста шапкой не считается")
    func чертаНеШапка() {
        let text = "Начало\n\n---\n\nПродолжение"
        let parts = ObsidianMarkdown.split(text)
        #expect(parts.front.isEmpty)
        #expect(parts.body == text)
    }

    @Test("Незакрытая шапка шапкой не считается")
    func незакрытаяШапка() {
        let text = "---\ntrunook: 123\nтекст без закрытия"
        #expect(ObsidianMarkdown.split(text).front.isEmpty)
    }

    @Test("Значение читается и в кавычках")
    func значениеВКавычках() {
        let front = ["related: \"[[Роадмап]]\"", "trunook: 8f4c"]
        #expect(ObsidianMarkdown.value(of: "trunook", in: front) == "8f4c")
        #expect(ObsidianMarkdown.value(of: "related", in: front) == "[[Роадмап]]")
        #expect(ObsidianMarkdown.value(of: "нет", in: front) == nil)
    }

    /// Свойства в чужой заметке ставил человек. Наша запись обязана менять
    /// только своё.
    @Test("Чужие свойства переживают нашу запись")
    func чужиеСвойстваЦелы() {
        let front = ["tags:", "  - работа", "status: в работе"]
        let updated = ObsidianMarkdown.setting("trunook", to: "8f4c", in: front)
        #expect(updated == front + ["trunook: 8f4c"])
    }

    @Test("Своё свойство заменяется, а не удваивается")
    func своёСвойствоЗаменяется() {
        let front = ["trunook: старое", "tags: работа"]
        let updated = ObsidianMarkdown.setting("trunook", to: "новое", in: front)
        #expect(updated == ["trunook: новое", "tags: работа"])
    }

    // MARK: - Перенос строки

    /// `\r\n` в Swift — один символ: привычные проверки на нём молча ничего
    /// не делают. Час на этом уже потрачен при описаниях выпусков.
    @Test("Чужие переносы строк разбираются целиком")
    func переносыCRLF() {
        let text = "---\r\ntrunook: 8f4c\r\n---\r\n\r\nтело заметки\r\n"
        let parts = ObsidianMarkdown.split(text)
        #expect(parts.front == ["trunook: 8f4c"], "шапка не должна утащить возврат каретки в значение")
        #expect(ObsidianMarkdown.value(of: "trunook", in: parts.front) == "8f4c")
        #expect(!parts.body.contains("\r\n"), "тело разобрано по строкам, а не по половине пары")
    }

    // MARK: - Блок связей

    @Test("Блок связей встаёт в конец и находится обратно")
    func блокСвязей() throws {
        let block = try #require(ObsidianMarkdown.linksBlock(lines: ["- [[Роадмап]] — про то же"]))
        let text = ObsidianMarkdown.settingLinks(block, in: "тело заметки")

        #expect(text.hasPrefix("тело заметки"))
        #expect(ObsidianMarkdown.linksBlock(in: text) == block)
        #expect(text.contains("[[Роадмап]]"))
    }

    @Test("Повторная запись заменяет блок, а не копит их")
    func блокНеКопится() throws {
        let first = try #require(ObsidianMarkdown.linksBlock(lines: ["- [[Первая]]"]))
        let second = try #require(ObsidianMarkdown.linksBlock(lines: ["- [[Вторая]]"]))

        var text = ObsidianMarkdown.settingLinks(first, in: "тело")
        text = ObsidianMarkdown.settingLinks(second, in: text)

        #expect(!text.contains("Первая"))
        #expect(text.contains("Вторая"))
        let starts = ObsidianMarkdown.lines(of: text).filter { $0 == ObsidianMarkdown.linksStart }
        #expect(starts.count == 1)
    }

    /// Главное правило записи в чужие файлы: вне меток — ни байта.
    @Test("Снятие блока возвращает текст в точности")
    func снятиеБлокаНеТрогаетТекст() throws {
        let original = "тело заметки\n\nвторой абзац"
        let block = try #require(ObsidianMarkdown.linksBlock(lines: ["- [[Роадмап]]"]))
        let text = ObsidianMarkdown.settingLinks(block, in: original)
        #expect(ObsidianMarkdown.settingLinks(nil, in: text) == original)
    }

    // MARK: - Разметка в оформленный текст

    @Test("Заголовок опознаётся по решётке любого уровня")
    func заголовокОпознаётся() {
        let text = ObsidianMarkdown.attributed(from: "### Заголовок")
        let font = text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.pointSize == Note.headingFontSize)
        #expect(text.string == "Заголовок", "решётки в текст не попадают")
    }

    @Test("Решётка без пробела заголовком не делает")
    func решёткаБезПробела() {
        let text = ObsidianMarkdown.attributed(from: "#тег в тексте")
        #expect(text.string == "#тег в тексте")
        let font = text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.pointSize == Note.bodyFontSize)
    }

    @Test("Ссылка становится ссылкой, а скобки уходят")
    func ссылкаРазбирается() throws {
        let text = ObsidianMarkdown.attributed(from: "смотри [сайт](https://trunook.ru) тут")
        #expect(text.string == "смотри сайт тут")
        let url = text.attribute(.link, at: 7, effectiveRange: nil) as? URL
        #expect(url?.absoluteString == "https://trunook.ru")
    }

    /// Ссылка Obsidian — не наша разметка, и трогать её нельзя: без скобок
    /// она перестанет быть ссылкой в графе.
    @Test("Ссылка Obsidian остаётся текстом как есть")
    func ссылкаObsidianНеТрогается() {
        let text = ObsidianMarkdown.attributed(from: "- [[Проекты/Роадмап]] — про то же")
        #expect(text.string == "- [[Проекты/Роадмап]] — про то же")
    }

    @Test("Умножение звёздочками курсивом не становится")
    func умножениеНеКурсив() {
        let text = ObsidianMarkdown.attributed(from: "5 * 3 * 2")
        #expect(text.string == "5 * 3 * 2")
    }

    @Test("Незакрытая звёздочка остаётся звёздочкой")
    func незакрытаяЗвёздочка() {
        let text = ObsidianMarkdown.attributed(from: "первый * второй")
        #expect(text.string == "первый * второй")
    }

    @Test("Внутри блока кода разметка не разбирается")
    func кодНеРазбирается() {
        let source = "```\nlet x = **не жирный**\n```"
        let text = ObsidianMarkdown.attributed(from: source)
        #expect(text.string == source)
    }

    // MARK: - Круг

    /// Ради этого всё и затевалось: заметка, проехавшая через файл и обратно,
    /// обязана вернуться той же. Списки и цитаты держатся в круге тем, что
    /// остаются простым текстом, — превращать их в красивое нельзя.
    @Test("Файл переживает круг «разметка — заметка — разметка»")
    func кругБезПотерь() {
        let source = """
        ## Заголовок

        Обычный текст с **жирным** и *курсивом*.

        - пункт списка
        - второй пункт

        > цитата

        [ссылка](https://trunook.ru)
        """
        let back = NoteMarkdown.body(ObsidianMarkdown.attributed(from: source))
        #expect(back == source)
    }

    @Test("Чужие переносы строк круг тоже переживают")
    func кругСЧужимиПереносами() {
        let back = NoteMarkdown.body(ObsidianMarkdown.attributed(from: "первая\r\nвторая"))
        #expect(back == "первая\nвторая")
    }

    // MARK: - Файл своей заметки

    @Test("Имя файла — имя заметки, без даты впереди")
    func имяФайлаСвоейЗаметки() {
        let note = Self.note(title: "Идея про вырез")
        #expect(ObsidianMarkdown.fileName(for: note) == "Идея про вырез.md")
    }

    @Test("Заметка без имени получает имя из даты")
    func имяФайлаБезЗаголовка() {
        let name = ObsidianMarkdown.fileName(for: Self.note(title: "   "))
        #expect(name.hasSuffix(".md"))
        #expect(name.first?.isNumber == true)
    }

    @Test("Запись своей заметки сохраняет чужие свойства и блок связей")
    func записьНеТеряетЧужого() throws {
        let block = try #require(ObsidianMarkdown.linksBlock(lines: ["- [[Роадмап]]"]))
        let existing = ObsidianMarkdown.join(
            front: ["tags: работа", "trunook: 8f4c"],
            body: ObsidianMarkdown.settingLinks(block, in: "старое тело")
        )

        let file = ObsidianMarkdown.file(for: Self.note(title: "Идея"), uid: "8f4c", existing: existing)
        let parts = ObsidianMarkdown.split(file)

        #expect(parts.front.contains("tags: работа"), "чужое свойство обязано уцелеть")
        #expect(ObsidianMarkdown.value(of: "trunook", in: parts.front) == "8f4c")
        #expect(ObsidianMarkdown.linksBlock(in: parts.body) == block, "блок связей обязан остаться")
        #expect(parts.body.contains("новое тело"))
        #expect(!parts.body.contains("старое тело"))
    }

    @Test("Дата создания уезжает в свойства и читается обратно")
    func датаСоздания() throws {
        let created = Date(timeIntervalSince1970: 1_757_000_000)
        let file = ObsidianMarkdown.file(
            for: Self.note(title: "Идея", createdAt: created),
            uid: "8f4c",
            existing: nil
        )
        let stored = try #require(ObsidianMarkdown.value(of: "created", in: ObsidianMarkdown.split(file).front))
        // Вид записи, а не конкретное значение: часовой пояс на разных
        // машинах разный, и сверка со строкой врала бы у половины из них.
        #expect(stored.count == 16, "«04.09.2026 19:33» — шестнадцать знаков")
        #expect(stored.dropFirst(2).hasPrefix("."), "день, месяц, год — точками")
        #expect(stored.contains(":"), "и время следом")
        #expect(!stored.contains("T"), "машинная запись человеку в свойствах не нужна")

        let back = try #require(ObsidianMarkdown.date(from: stored))
        // Секунд в записи нет — по ним и расходимся, не больше чем на минуту.
        #expect(abs(back.timeIntervalSince(created)) < 60)
    }

    /// Файлы, записанные до смены формата, лежат у людей на дисках. Отказ
    /// их прочитать означал бы потерянную дату создания у каждой такой
    /// заметки.
    @Test("Старая запись даты ISO читается по-прежнему")
    func стараяДатаЧитается() throws {
        let back = try #require(ObsidianMarkdown.date(from: "2026-09-04T19:46:46Z"))
        #expect(abs(back.timeIntervalSince1970 - 1_788_551_206) < 1)
    }

    @Test("Показывают тело без шапки и без связей")
    func телоДляПоказа() throws {
        let block = try #require(ObsidianMarkdown.linksBlock(lines: ["- [[Роадмап]]"]))
        let file = ObsidianMarkdown.join(
            front: ["tags: работа"],
            body: ObsidianMarkdown.settingLinks(block, in: "тело заметки")
        )
        #expect(ObsidianMarkdown.readableBody(of: file) == "тело заметки")
    }

    // MARK: - Обвязка

    private static func note(title: String, createdAt: Date = Date()) -> Note {
        let text = NSAttributedString(
            string: "новое тело",
            attributes: [.font: NSFont.systemFont(ofSize: Note.bodyFontSize)]
        )
        let rtf = text.rtf(from: NSRange(location: 0, length: text.length), documentAttributes: [:]) ?? Data()
        return Note(
            id: 1,
            title: title,
            rtf: rtf,
            plain: text.string,
            createdAt: createdAt,
            updatedAt: createdAt,
            origin: .typed,
            titleByModel: false
        )
    }
}

/// Сверка базы с папкой. Все ветки решения — здесь: это самое опасное место
/// всей работы, и наблюдением за живой папкой его не проверить.
@Suite("Сверка с хранилищем")
struct SyncPlanTests {
    // MARK: - Отказы

    /// Отключённый внешний диск, недокачанный iCloud и переименованная папка
    /// выглядят одинаково. Принять это за «человек всё удалил» — значит
    /// вычистить базу.
    @Test("Недоступная папка останавливает сверку")
    func недоступнаяПапка() {
        let outcome = SyncPlan.make(Self.input(isReachable: false, notes: [Self.note()]))
        #expect(outcome == .refused(.unreachable))
    }

    @Test("Опустевшее хранилище останавливает сверку")
    func опустевшееХранилище() {
        let outcome = SyncPlan.make(
            Self.input(otherFiles: [Self.file(path: "Одна.md")], knownFiles: 40)
        )
        #expect(outcome == .refused(.emptied(known: 40, found: 1)))
    }

    /// У хранилища из трёх заметок удаление двух — обычное дело, а не беда.
    @Test("У крошечного хранилища убыль бедой не считается")
    func крошечноеХранилище() {
        let outcome = SyncPlan.make(
            Self.input(otherFiles: [Self.file(path: "Одна.md")], knownFiles: 3)
        )
        #expect(outcome != .refused(.emptied(known: 3, found: 1)))
    }

    // MARK: - Своя заметка

    @Test("Новая заметка уходит в файл, имя ей назначат при записи")
    func новаяЗаметка() {
        let actions = Self.actions(Self.input(notes: [Self.note(id: 1, uid: "a")]))
        #expect(actions == [.writeOwn(noteID: 1, path: nil)])
    }

    @Test("Правка в приложении уходит в файл")
    func правкаВПриложении() {
        let actions = Self.actions(
            Self.input(
                notes: [Self.note(id: 1, uid: "a", updatedAt: Self.later)],
                bookmarks: [Self.bookmark(uid: "a")],
                ownFiles: [Self.ownFile(uid: "a")]
            )
        )
        #expect(actions == [.writeOwn(noteID: 1, path: "Trunook/Идея.md")])
    }

    @Test("Правка в Obsidian приезжает в заметку")
    func правкаВObsidian() {
        let actions = Self.actions(
            Self.input(
                notes: [Self.note(id: 1, uid: "a")],
                bookmarks: [Self.bookmark(uid: "a", hash: "старый")],
                ownFiles: [Self.ownFile(uid: "a", hash: "новый")]
            )
        )
        #expect(actions == [.acceptOwn(noteID: 1, path: "Trunook/Идея.md")])
    }

    @Test("Правка с обеих сторон становится спором")
    func правкаСОбеихСторон() {
        let actions = Self.actions(
            Self.input(
                notes: [Self.note(id: 1, uid: "a", updatedAt: Self.later)],
                bookmarks: [Self.bookmark(uid: "a", hash: "старый")],
                ownFiles: [Self.ownFile(uid: "a", hash: "новый")]
            )
        )
        #expect(actions == [.conflict(noteID: 1, path: "Trunook/Идея.md")])
    }

    /// Своя же запись возвращается событием файловой системы со свежей датой.
    /// Не сойдись отпечатки — сверка приняла бы её за чужую правку, и запись
    /// с чтением пошли бы по кругу.
    @Test("Нетронутая пара не даёт ни одного действия")
    func ничегоНеМенялось() {
        let actions = Self.actions(
            Self.input(
                notes: [Self.note(id: 1, uid: "a")],
                bookmarks: [Self.bookmark(uid: "a")],
                ownFiles: [Self.ownFile(uid: "a")]
            )
        )
        #expect(actions.isEmpty)
    }

    /// Заметка узнаётся по номеру в шапке, а не по пути, — иначе
    /// переименование выглядело бы как «одну удалили, другую завели».
    @Test("Переименование в Obsidian доезжает до имени заметки")
    func переименованиеВObsidian() {
        let actions = Self.actions(
            Self.input(
                notes: [Self.note(id: 1, uid: "a")],
                bookmarks: [Self.bookmark(uid: "a", path: "Trunook/Идея.md")],
                ownFiles: [Self.ownFile(uid: "a", path: "Trunook/Идея про вырез.md")]
            )
        )
        #expect(actions == [.acceptOwn(noteID: 1, path: "Trunook/Идея про вырез.md")])
    }

    @Test("Файл удалили в Obsidian — уходит и заметка")
    func файлУдалилиВObsidian() {
        let actions = Self.actions(
            Self.input(notes: [Self.note(id: 1, uid: "a")], bookmarks: [Self.bookmark(uid: "a")])
        )
        #expect(actions == [.deleteOwn(noteID: 1)])
    }

    @Test("Заметку удалили в приложении — файл уходит в Корзину")
    func заметкуУдалилиВПриложении() {
        let actions = Self.actions(
            Self.input(bookmarks: [Self.bookmark(uid: "a")], ownFiles: [Self.ownFile(uid: "a")])
        )
        #expect(actions == [.trashOwn(path: "Trunook/Идея.md"), .forget(noteID: 1)])
    }

    @Test("Закладка без заметки и без файла просто забывается")
    func закладкаНиОЧём() {
        let actions = Self.actions(Self.input(bookmarks: [Self.bookmark(uid: "a")]))
        #expect(actions == [.forget(noteID: 1)])
    }

    @Test("Файл, положенный человеком в нашу папку, становится своей заметкой")
    func чужойФайлВСвоейПапке() {
        let actions = Self.actions(
            Self.input(ownFiles: [Self.ownFile(uid: nil, path: "Trunook/Своими руками.md")])
        )
        #expect(actions == [.adoptOwn(path: "Trunook/Своими руками.md")])
    }

    /// После переустановки приложения база пуста, а файлы на месте.
    @Test("Файл без закладки принимается, а не перетирается")
    func файлБезЗакладки() {
        let actions = Self.actions(
            Self.input(notes: [Self.note(id: 1, uid: "a")], ownFiles: [Self.ownFile(uid: "a")])
        )
        #expect(actions == [.acceptOwn(noteID: 1, path: "Trunook/Идея.md")])
    }

    // MARK: - Зеркала хранилища

    @Test("Незнакомая заметка хранилища заводит зеркало")
    func новоеЗеркало() {
        let actions = Self.actions(Self.input(otherFiles: [Self.file(path: "Проекты/Роадмап.md")]))
        #expect(actions == [.importMirror(path: "Проекты/Роадмап.md")])
    }

    @Test("Изменившийся файл хранилища перечитывается")
    func зеркалоИзменилось() {
        let actions = Self.actions(
            Self.input(
                mirrors: [Self.mirror(path: "Проекты/Роадмап.md", size: 100)],
                otherFiles: [Self.file(path: "Проекты/Роадмап.md", size: 120)]
            )
        )
        #expect(actions == [.updateMirror(noteID: 7, path: "Проекты/Роадмап.md")])
    }

    /// Дата правки едет из файловой системы дробной, а хранится вещественным
    /// числом. Точное сравнение врало бы «изменилось» на каждой сверке.
    @Test("Дробная доля даты за правку не принимается")
    func дробнаяДоляДаты() {
        let actions = Self.actions(
            Self.input(
                mirrors: [Self.mirror(path: "Заметка.md", modified: Self.now)],
                otherFiles: [Self.file(path: "Заметка.md", modified: Self.now.addingTimeInterval(0.4))]
            )
        )
        #expect(actions.isEmpty)
    }

    @Test("Пропавший файл хранилища убирает зеркало")
    func зеркалоПропало() {
        let actions = Self.actions(
            Self.input(
                mirrors: [Self.mirror(path: "Проекты/Роадмап.md")],
                otherFiles: [Self.file(path: "Другое.md"), Self.file(path: "Третье.md")],
                knownFiles: 3
            )
        )
        #expect(actions.contains(.dropMirror(noteID: 7)))
    }

    /// Выключенное чтение хранилища не должно ни трогать файлы, ни оставлять
    /// чужие заметки в поиске.
    @Test("Выключенное чтение хранилища убирает зеркала и не заводит новых")
    func чтениеХранилищаВыключено() {
        let actions = Self.actions(
            Self.input(
                indexVault: false,
                mirrors: [Self.mirror(path: "Проекты/Роадмап.md")],
                otherFiles: [Self.file(path: "Новая.md")]
            )
        )
        #expect(actions == [.dropMirror(noteID: 7)])
    }

    // MARK: - Обвязка

    private static let now = Date(timeIntervalSince1970: 1_757_000_000)
    private static let later = now.addingTimeInterval(60)

    private static func input(
        isReachable: Bool = true,
        indexVault: Bool = true,
        notes: [SyncNote] = [],
        bookmarks: [OwnBookmark] = [],
        ownFiles: [OwnFile] = [],
        mirrors: [MirrorBookmark] = [],
        otherFiles: [VaultFile] = [],
        knownFiles: Int = 0
    ) -> SyncPlan.Input {
        SyncPlan.Input(
            vault: Vault(url: URL(fileURLWithPath: "/tmp/Мысли")),
            isReachable: isReachable,
            indexVault: indexVault,
            notes: notes,
            bookmarks: bookmarks,
            ownFiles: ownFiles,
            mirrors: mirrors,
            otherFiles: otherFiles,
            knownFiles: knownFiles
        )
    }

    private static func actions(_ input: SyncPlan.Input) -> [SyncAction] {
        guard case let .actions(list) = SyncPlan.make(input) else { return [] }
        return list
    }

    private static func note(id: Int64 = 1, uid: String = "a", updatedAt: Date = now) -> SyncNote {
        SyncNote(id: id, uid: uid, updatedAt: updatedAt)
    }

    private static func bookmark(
        noteID: Int64 = 1,
        uid: String,
        path: String = "Trunook/Идея.md",
        hash: String = "отпечаток",
        syncedAt: Date = now
    ) -> OwnBookmark {
        OwnBookmark(noteID: noteID, uid: uid, path: path, hash: hash, syncedAt: syncedAt)
    }

    private static func ownFile(
        uid: String?,
        path: String = "Trunook/Идея.md",
        hash: String = "отпечаток"
    ) -> OwnFile {
        OwnFile(path: path, uid: uid, modified: now, hash: hash)
    }

    private static func mirror(
        noteID: Int64 = 7,
        path: String,
        modified: Date = now,
        size: Int = 100
    ) -> MirrorBookmark {
        MirrorBookmark(noteID: noteID, path: path, modified: modified, size: size)
    }

    private static func file(path: String, modified: Date = now, size: Int = 100) -> VaultFile {
        VaultFile(path: path, modified: modified, size: size)
    }
}

/// Закладки сверки и достройка схемы заметок.
@Suite("Закладки хранилища")
struct ObsidianStoreTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("trunook-obsidian-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
    }

    @Test("Закладка своей заметки ложится и читается обратно")
    func закладкаСвоей() throws {
        let store = ObsidianStore(url: temporaryURL())
        let synced = Date(timeIntervalSince1970: 1_757_000_000)
        let bookmark = OwnBookmark(
            noteID: 42,
            uid: "8f4c",
            path: "Trunook/Идея.md",
            hash: "отпечаток",
            syncedAt: synced
        )
        store.put(own: bookmark, modified: synced, size: 1843)

        let back = try #require(store.own().first)
        #expect(back == bookmark)
        #expect(store.mirrors().isEmpty, "своя заметка зеркалом не считается")
    }

    @Test("Закладка зеркала помнит дату и размер файла")
    func закладкаЗеркала() throws {
        let store = ObsidianStore(url: temporaryURL())
        let mirror = MirrorBookmark(
            noteID: 7,
            path: "Проекты/Роадмап.md",
            modified: Date(timeIntervalSince1970: 1_757_000_000),
            size: 1843
        )
        store.put(mirror: mirror)

        #expect(store.mirrors() == [mirror])
        #expect(store.own().isEmpty)
    }

    @Test("Повторная запись заменяет закладку, а не удваивает")
    func закладкаНеУдваивается() {
        let store = ObsidianStore(url: temporaryURL())
        let now = Date()
        for path in ["Trunook/Первое имя.md", "Trunook/Второе имя.md"] {
            store.put(
                own: OwnBookmark(noteID: 1, uid: "8f4c", path: path, hash: "х", syncedAt: now),
                modified: now,
                size: 10
            )
        }
        #expect(store.own().count == 1)
        #expect(store.own().first?.path == "Trunook/Второе имя.md")
    }

    @Test("Путь находит свою заметку")
    func путьНаходитЗаметку() {
        let store = ObsidianStore(url: temporaryURL())
        let now = Date()
        store.put(
            own: OwnBookmark(noteID: 42, uid: "8f4c", path: "Trunook/Идея.md", hash: "х", syncedAt: now),
            modified: now,
            size: 10
        )
        #expect(store.noteID(forPath: "Trunook/Идея.md") == 42)
        #expect(store.noteID(forPath: "Trunook/Чужое.md") == nil)
    }

    /// Так выглядит выключенная синхронизация: связь с папкой разорвана,
    /// а заметки и файлы целы.
    @Test("Очистка закладок не трогает ничего, кроме закладок")
    func очисткаЗакладок() {
        let url = temporaryURL()
        let notes = NotesStore(url: url)
        let store = ObsidianStore(url: url)
        let now = Date()

        let id = notes.insert(
            Note(id: Note.unsaved, title: "Идея", rtf: Data(), plain: "текст",
                 createdAt: now, updatedAt: now, origin: .typed, titleByModel: false)
        )
        store.put(
            own: OwnBookmark(noteID: id ?? 1, uid: "8f4c", path: "Trunook/Идея.md", hash: "х", syncedAt: now),
            modified: now,
            size: 10
        )

        store.forgetAll()
        #expect(store.own().isEmpty)
        #expect(notes.count == 1, "заметка обязана остаться")
    }

    @Test("Число известных файлов считает обе половины")
    func числоИзвестныхФайлов() {
        let store = ObsidianStore(url: temporaryURL())
        let now = Date()
        store.put(
            own: OwnBookmark(noteID: 1, uid: "a", path: "Trunook/Идея.md", hash: "х", syncedAt: now),
            modified: now,
            size: 10
        )
        store.put(mirror: MirrorBookmark(noteID: 2, path: "Проекты/Роадмап.md", modified: now, size: 10))
        #expect(store.knownFiles == 2)
    }

    // MARK: - Схема заметок

    @Test("Новая заметка получает постоянный номер")
    func заметкаПолучаетНомер() throws {
        let store = NotesStore(url: temporaryURL())
        let now = Date()
        _ = store.insert(
            Note(id: Note.unsaved, title: "Идея", rtf: Data(), plain: "текст",
                 createdAt: now, updatedAt: now, origin: .typed, titleByModel: false)
        )
        let note = try #require(store.all().first)
        #expect(!note.uid.isEmpty, "без номера заметка не найдёт свой файл после переименования")
    }

    @Test("Номера у двух заметок разные")
    func номераРазные() {
        let store = NotesStore(url: temporaryURL())
        let now = Date()
        for title in ["Первая", "Вторая"] {
            _ = store.insert(
                Note(id: Note.unsaved, title: title, rtf: Data(), plain: title,
                     createdAt: now, updatedAt: now, origin: .typed, titleByModel: false)
            )
        }
        #expect(Set(store.all().map(\.uid)).count == 2)
    }

    /// База, заведённая прежней версией, номеров не знает: `CREATE TABLE
    /// IF NOT EXISTS` её не меняет вовсе. Колонку достраивают руками,
    /// и накопленные заметки получают номера тем же заходом.
    @Test("Накопленные заметки получают номера при достройке схемы")
    func миграцияРаздаётНомера() throws {
        let url = temporaryURL()
        let old = NotesStore(url: url)
        let now = Date()
        _ = old.insert(
            Note(id: Note.unsaved, title: "Старая", rtf: Data(), plain: "текст",
                 createdAt: now, updatedAt: now, origin: .typed, titleByModel: false)
        )

        // Возвращаем базу к прежнему виду и открываем заново — так же,
        // как это случится у человека при обновлении.
        try dropUIDColumn(at: url)
        let fresh = NotesStore(url: url)
        let note = try #require(fresh.all().first)
        #expect(!note.uid.isEmpty)
    }

    @Test("Заметки хранилища отделяются от своих в списке и в поиске")
    func источникиРазделяются() {
        let store = NotesStore(url: temporaryURL())
        let now = Date()
        _ = store.insert(
            Note(id: Note.unsaved, title: "Своя про вырез", rtf: Data(), plain: "вырез",
                 createdAt: now, updatedAt: now, origin: .typed, titleByModel: false)
        )
        _ = store.insert(
            Note(id: Note.unsaved, title: "Чужая про вырез", rtf: Data(), plain: "вырез",
                 createdAt: now, updatedAt: now.addingTimeInterval(60), origin: .obsidian, titleByModel: false)
        )

        #expect(store.all(source: .own).map(\.title) == ["Своя про вырез"])
        #expect(store.all(source: .vault).map(\.title) == ["Чужая про вырез"])
        #expect(store.count(source: .own) == 1)
        #expect(
            store.search("вырез").map(\.title) == ["Своя про вырез", "Чужая про вырез"],
            "своя впереди, хотя чужая свежее"
        )
    }

    /// Возвращает таблицу к виду без номера — так она выглядит у того,
    /// кто обновляется с прежней версии.
    private func dropUIDColumn(at url: URL) throws {
        let script = """
            ALTER TABLE notes RENAME TO notes_old;
            CREATE TABLE notes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL, rtf BLOB NOT NULL, plain TEXT NOT NULL,
                folded TEXT NOT NULL, createdAt REAL NOT NULL, updatedAt REAL NOT NULL,
                origin TEXT NOT NULL, titleByModel INTEGER NOT NULL);
            INSERT INTO notes SELECT id, title, rtf, plain, folded, createdAt, updatedAt, origin, titleByModel
                FROM notes_old;
            DROP TABLE notes_old;
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [url.path, script]
        try process.run()
        process.waitUntilExit()
    }
}

/// Сквозная проверка службы: живая папка, живая база, полный круг.
///
/// Чистое решение проверяет `SyncPlan`; здесь проверяется исполнение —
/// то, что действия и правда доводят файлы и заметки до нужного вида.
@Suite("Синхронизация с Obsidian")
struct ObsidianServiceTests {
    // MARK: - Обвязка

    private struct World {
        let vault: Vault
        let notes: NotesStore
        let service: ObsidianService
        let settings: Settings
    }

    private func makeWorld(enabled: Bool = true, indexVault: Bool = true) throws -> World {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("trunook-sync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".obsidian"),
            withIntermediateDirectories: true
        )

        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("trunook-sync-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        let settings = Settings(defaults: UserDefaults(suiteName: "trunook-tests-\(UUID().uuidString)")!)
        settings.ollamaEnabled = false
        settings.obsidianEnabled = enabled
        settings.obsidianVaultPath = root.path
        settings.obsidianIndexVault = indexVault

        let notes = NotesStore(url: base)
        return World(
            vault: Vault(url: root),
            notes: notes,
            service: ObsidianService(
                store: notes,
                bookmarks: ObsidianStore(url: base),
                settings: settings
            ),
            settings: settings
        )
    }

    private func remove(_ world: World) {
        try? FileManager.default.removeItem(at: world.vault.url)
    }

    @discardableResult
    private func addNote(_ title: String, text: String, to store: NotesStore) -> Int64 {
        let attributed = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: Note.bodyFontSize)]
        )
        let rtf = attributed.rtf(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [:]
        ) ?? Data()
        let now = Date()
        return store.insert(
            Note(id: Note.unsaved, title: title, rtf: rtf, plain: text,
                 createdAt: now, updatedAt: now, origin: .typed, titleByModel: false)
        ) ?? 0
    }

    private func put(_ text: String, at path: String, in vault: Vault) throws {
        let url = vault.fileURL(for: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Своя заметка

    @Test("Своя заметка выкладывается в хранилище с номером в шапке")
    func заметкаВыкладывается() throws {
        let world = try makeWorld()
        defer { remove(world) }

        addNote("Идея про вырез", text: "мысль", to: world.notes)
        world.service.syncSynchronously()

        let text = try #require(VaultScanner.text(at: "Trunook/Идея про вырез.md", in: world.vault))
        let front = ObsidianMarkdown.split(text).front
        #expect(ObsidianMarkdown.value(of: ObsidianMarkdown.Key.uid, in: front) != nil)
        #expect(text.contains("мысль"))
    }

    /// Своя же запись возвращается событием файловой системы. Не узнай сверка
    /// собственный отпечаток — запись и чтение пошли бы по кругу.
    @Test("Повторная сверка не переписывает ничего")
    func повторнаяСверкаТиха() throws {
        let world = try makeWorld()
        defer { remove(world) }

        addNote("Идея", text: "мысль", to: world.notes)
        world.service.syncSynchronously()
        let after = try #require(VaultScanner.text(at: "Trunook/Идея.md", in: world.vault))

        world.service.syncSynchronously()
        #expect(VaultScanner.text(at: "Trunook/Идея.md", in: world.vault) == after)
        #expect(VaultScanner.files(in: world.vault).count == 1, "второго файла появиться не должно")
        #expect(world.notes.count == 1, "и второй заметки тоже")
    }

    @Test("Правка в Obsidian приезжает в заметку")
    func правкаИзObsidian() throws {
        let world = try makeWorld()
        defer { remove(world) }

        addNote("Идея", text: "старая мысль", to: world.notes)
        world.service.syncSynchronously()

        let text = try #require(VaultScanner.text(at: "Trunook/Идея.md", in: world.vault))
        try put(text.replacingOccurrences(of: "старая мысль", with: "новая мысль"),
                at: "Trunook/Идея.md", in: world.vault)
        world.service.syncSynchronously()

        let note = try #require(world.notes.all(source: .own).first)
        #expect(note.plain.contains("новая мысль"))
        #expect(!note.plain.contains("старая"))
    }

    /// Имя файла — это и есть имя заметки: в Obsidian на неё ссылаются так.
    /// Заметка узнаётся по номеру в шапке, поэтому переименование остаётся
    /// переименованием.
    @Test("Переименование файла меняет имя заметки, а не заводит новую")
    func переименованиеФайла() throws {
        let world = try makeWorld()
        defer { remove(world) }

        addNote("Идея", text: "мысль", to: world.notes)
        world.service.syncSynchronously()

        try FileManager.default.moveItem(
            at: world.vault.fileURL(for: "Trunook/Идея.md"),
            to: world.vault.fileURL(for: "Trunook/Идея про вырез.md")
        )
        world.service.syncSynchronously()

        let notes = world.notes.all(source: .own)
        #expect(notes.count == 1, "переименование — не «одну удалили, другую завели»")
        #expect(notes.first?.title == "Идея про вырез")
    }

    @Test("Файл, удалённый в Obsidian, уносит и заметку")
    func файлУдалили() throws {
        let world = try makeWorld()
        defer { remove(world) }

        addNote("Идея", text: "мысль", to: world.notes)
        world.service.syncSynchronously()
        try FileManager.default.removeItem(at: world.vault.fileURL(for: "Trunook/Идея.md"))
        world.service.syncSynchronously()

        #expect(world.notes.count == 0)
    }

    @Test("Файл, положенный человеком в нашу папку, становится заметкой")
    func файлВСвоейПапке() throws {
        let world = try makeWorld()
        defer { remove(world) }

        try put("# Заголовок\n\nсвоими руками", at: "Trunook/Своими руками.md", in: world.vault)
        world.service.syncSynchronously()

        let note = try #require(world.notes.all(source: .own).first)
        #expect(note.title == "Своими руками")
        #expect(note.plain.contains("своими руками"))

        let text = try #require(VaultScanner.text(at: "Trunook/Своими руками.md", in: world.vault))
        let uid = ObsidianMarkdown.value(of: ObsidianMarkdown.Key.uid, in: ObsidianMarkdown.split(text).front)
        #expect(uid == note.uid, "номер обязан лечь в файл сразу, иначе переименование потеряет заметку")
    }

    // MARK: - Заметки хранилища

    @Test("Заметка хранилища становится зеркалом и находится поиском")
    func зеркалоИПоиск() throws {
        let world = try makeWorld()
        defer { remove(world) }

        try put("# Роадмап\n\nпро раскрытие панели", at: "Проекты/Роадмап.md", in: world.vault)
        world.service.syncSynchronously()

        let found = world.notes.search("раскрытие")
        #expect(found.count == 1)
        #expect(found.first?.origin == .obsidian)
        #expect(found.first?.title == "Роадмап")
        #expect(world.notes.all(source: .own).isEmpty, "чужая заметка своей не становится")
    }

    @Test("Выключенное чтение хранилища зеркал не заводит")
    func чтениеХранилищаВыключено() throws {
        let world = try makeWorld(indexVault: false)
        defer { remove(world) }

        try put("про раскрытие панели", at: "Проекты/Роадмап.md", in: world.vault)
        world.service.syncSynchronously()
        #expect(world.notes.all(source: .vault).isEmpty)
    }

    // MARK: - Выключено и недоступно

    /// Главное требование ко всей работе: у того, у кого Obsidian нет,
    /// приложение обязано вести себя ровно так же, как до неё.
    @Test("Выключенная синхронизация не трогает ни базы, ни папки")
    func выключенаЦеликом() throws {
        let world = try makeWorld(enabled: false)
        defer { remove(world) }

        addNote("Идея", text: "мысль", to: world.notes)
        try put("чужая заметка", at: "Проекты/Роадмап.md", in: world.vault)

        #expect(world.service.syncSynchronously() == .off)
        #expect(world.notes.count == 1, "своя заметка на месте")
        #expect(world.notes.all(source: .vault).isEmpty, "зеркал не завелось")
        #expect(!FileManager.default.fileExists(atPath: world.vault.ownFolder.path), "папки не завелось")
    }

    @Test("Не выбранная папка — это состояние, а не поломка")
    func папкаНеВыбрана() throws {
        let world = try makeWorld()
        defer { remove(world) }
        world.settings.obsidianVaultPath = ""
        #expect(world.service.syncSynchronously() == .noFolder)
    }

    /// Отключённый внешний диск выглядит как «файлов нет». Принять это
    /// за «человек всё удалил» — значит вычистить базу.
    @Test("Пропавшая папка не удаляет ни одной заметки")
    func пропавшаяПапка() throws {
        let world = try makeWorld()
        defer { remove(world) }

        addNote("Идея", text: "мысль", to: world.notes)
        world.service.syncSynchronously()

        world.settings.obsidianVaultPath = world.vault.url.path + "-которой-нет"
        #expect(world.service.syncSynchronously() == .unreachable)
        #expect(world.notes.count == 1, "заметка обязана уцелеть")
    }
}

/// Своя папка внутри хранилища: имя задаёт человек, и оно бывает вложенным.
@Suite("Папка для своих заметок")
struct VaultFolderTests {
    @Test("Вложенная папка считается своей")
    func вложеннаяПапка() {
        let vault = Vault(url: URL(fileURLWithPath: "/tmp/Мысли"), folder: "Заметки/Trunook")
        #expect(vault.isOwn("Заметки/Trunook/Идея.md"))
        #expect(!vault.isOwn("Заметки/Идея.md"), "уровнем выше — уже чужое")
        #expect(vault.ownPath(fileName: "Идея.md") == "Заметки/Trunook/Идея.md")
    }

    @Test("Имя папки без косых работает как прежде")
    func простаяПапка() {
        let vault = Vault(url: URL(fileURLWithPath: "/tmp/Мысли"), folder: "Мои записи")
        #expect(vault.isOwn("Мои записи/Идея.md"))
        #expect(vault.ownFolder.lastPathComponent == "Мои записи")
    }

    @Test("Пробелы вокруг имени не заводят вторую папку")
    func пробелыСрезаются() {
        let vault = Vault(url: URL(fileURLWithPath: "/tmp/Мысли"), folder: "  Trunook  ")
        #expect(vault.folder == "Trunook")
    }
}
