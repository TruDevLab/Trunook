import Foundation
import Testing
@testable import Trunook

@Suite("Номер версии")
struct AppVersionTests {
    private func version(_ text: String) throws -> AppVersion {
        try #require(AppVersion(text))
    }

    /// Главная причина, по которой версия — не строка. В ряду версий этого
    /// проекта 0.9.0 и 0.10.0 стоят рядом, а строкой «0.9.0» больше «0.10.0».
    @Test("0.10.0 новее 0.9.0, хотя строкой это не так")
    func десятаяНовееДевятой() throws {
        #expect(try version("0.9.0") < version("0.10.0"))
        #expect("0.9.0" > "0.10.0")
    }

    /// Тег GitHub всегда с ведущей «v», версия в бандле — всегда без неё.
    /// Сравнивать приходится именно эту пару.
    @Test("Тег с «v» сравнивается с версией из бандла")
    func тегИБандл() throws {
        #expect(try version("0.11.1") < version("v0.12.0"))
        #expect(try version("v0.11.1") == version("0.11.1"))
    }

    @Test("Равные версии не новее друг друга")
    func равныеНеНовее() throws {
        let left = try version("0.11.1")
        let right = try version("0.11.1")
        #expect(!(left < right))
        #expect(!(right < left))
    }

    /// Хвостовые нули дописывать необязательно: 0.11 и 0.11.0 — одно и то же.
    /// Без нормализации сравнение массивов сочло бы их разными.
    @Test("0.11 и 0.11.0 — одна версия")
    func хвостовыеНули() throws {
        #expect(try version("0.11") == version("0.11.0"))
        #expect(try version("0.11.0.0") == version("0.11"))
    }

    @Test("Четвёртая часть номера учитывается")
    func четвёртаяЧасть() throws {
        #expect(try version("0.11.1") < version("0.11.1.1"))
    }

    /// Разбор обязан не падать на том, чего не ждал: сеть приносит что угодно.
    @Test("Мусор версией не становится")
    func мусор() {
        #expect(AppVersion("") == nil)
        #expect(AppVersion("не версия") == nil)
        #expect(AppVersion("v") == nil)
    }

    /// Предрелизов `/releases/latest` не отдаёт, но если такой номер однажды
    /// придёт, он не должен выглядеть новее выпуска.
    @Test("Предрелиз младше выпуска с тем же номером")
    func предрелиз() throws {
        #expect(try version("0.12.0-beta.1") < version("0.12.0"))
    }

    /// Формат показа из `AppInfo.version` — не предрелиз: скобка с номером
    /// сборки не должна делать версию младше.
    @Test("Номер сборки в скобках не считается хвостом предрелиза")
    func скобкиНеХвост() throws {
        #expect(try version("0.11.1 (2608301645)") == version("0.11.1"))
    }

    @Test("Показывается номер так, как он записан")
    func запись() throws {
        #expect(try version("v0.12.0").text == "0.12.0")
    }
}

@Suite("Выпуск на GitHub")
struct GitHubReleaseTests {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    /// Ответ обрезан до тех полей, которые читаются. Записанной строкой,
    /// а не живым запросом: лимит GitHub — 60 обращений в час, и отладка
    /// разбора съела бы его за десять минут.
    private let answer = """
    {"tag_name":"v0.12.0","name":"Trunook-0.12.0","draft":false,"prerelease":false,
     "html_url":"https://github.com/TruDevLab/Trunook/releases/tag/v0.12.0",
     "body":"## Установка\\n\\n`shasum -a 256`:\\n`65d4ac8a95da10e7dbcb4c3cc9ab4908c1acb02a2729823d6cd379977f09e391`\\n",
     "assets":[{"name":"Trunook-0.12.0.dmg","size":3557214,
                "browser_download_url":"https://github.com/TruDevLab/Trunook/releases/download/v0.12.0/Trunook-0.12.0.dmg"}]}
    """

    @Test("Выпуск разбирается целиком")
    func выпускРазбирается() throws {
        let release = try #require(GitHubRelease.parse(data(answer)))
        #expect(release.tag == "v0.12.0")
        #expect(release.version.text == "0.12.0")
        #expect(release.assetName == "Trunook-0.12.0.dmg")
        #expect(release.assetSize == 3_557_214)
        #expect(release.checksum == "65d4ac8a95da10e7dbcb4c3cc9ab4908c1acb02a2729823d6cd379977f09e391")
    }

    /// Порядок ассетов GitHub не обещает, и однажды рядом с образом окажется
    /// что-то ещё. Брать первый попавшийся нельзя.
    @Test("Образ находится среди чужих ассетов")
    func образСредиЧужих() throws {
        let release = try #require(GitHubRelease.parse(data("""
        {"tag_name":"v0.12.0","assets":[
          {"name":"checksums.txt","size":80,"browser_download_url":"https://example.com/checksums.txt"},
          {"name":"Trunook-0.12.0.dmg","size":10,"browser_download_url":"https://example.com/Trunook-0.12.0.dmg"}]}
        """)))
        #expect(release.assetName == "Trunook-0.12.0.dmg")
    }

    /// Выпуск без образа — это не «выпуска нет», а «выпуск негодный».
    /// Ставить из него нечего, и притворяться, что всё хорошо, нельзя.
    @Test("Выпуск без образа отбрасывается")
    func безОбраза() {
        #expect(GitHubRelease.parse(data("""
        {"tag_name":"v0.12.0","assets":[{"name":"Notes.txt","size":80,
          "browser_download_url":"https://example.com/Notes.txt"}]}
        """)) == nil)
    }

    @Test("Черновик и предрелиз не считаются выпуском")
    func черновик() {
        #expect(GitHubRelease.parse(data("""
        {"tag_name":"v0.12.0","draft":true,"assets":[{"name":"a.dmg","size":1,
          "browser_download_url":"https://example.com/a.dmg"}]}
        """)) == nil)
        #expect(GitHubRelease.parse(data("""
        {"tag_name":"v0.12.0","prerelease":true,"assets":[{"name":"a.dmg","size":1,
          "browser_download_url":"https://example.com/a.dmg"}]}
        """)) == nil)
    }

    @Test("Пустой и негодный ответ не роняют разбор")
    func негодныйОтвет() {
        #expect(GitHubRelease.parse(data("{}")) == nil)
        #expect(GitHubRelease.parse(data("не json вовсе")) == nil)
        #expect(GitHubRelease.parse(data("[]")) == nil)
    }

    /// Сумму переносит рукой человек, и однажды он её забудет. Это не повод
    /// отказываться от обновления: сумма ловит битую закачку, а подлинность
    /// проверяется подписью.
    @Test("Описание без суммы оставляет выпуск годным")
    func безСуммы() throws {
        let release = try #require(GitHubRelease.parse(data("""
        {"tag_name":"v0.12.0","body":"Просто описание без всяких сумм.",
         "assets":[{"name":"a.dmg","size":1,"browser_download_url":"https://example.com/a.dmg"}]}
        """)))
        #expect(release.checksum == nil)
    }

    /// Ищется не строка «shasum», а само слово из 64 знаков: разметка описания
    /// живёт в `RELEASE.md` и однажды изменится.
    @Test("Сумма находится вне зависимости от разметки вокруг")
    func суммаБезРазметки() {
        let hash = "65d4ac8a95da10e7dbcb4c3cc9ab4908c1acb02a2729823d6cd379977f09e391"
        #expect(GitHubRelease.checksum(inBody: "SHA-256 = \(hash)") == hash)
        #expect(GitHubRelease.checksum(inBody: "`\(hash)`") == hash)
        #expect(GitHubRelease.checksum(inBody: hash.uppercased()) == hash)
    }

    /// Слово из 64 знаков, среди которых есть не шестнадцатеричные, суммой
    /// не является, а слово из 128 — тем более не содержит её внутри.
    @Test("Похожее на сумму, но не сумма, не берётся")
    func похожееНеБерётся() {
        #expect(GitHubRelease.checksum(inBody: String(repeating: "z", count: 64)) == nil)
        #expect(GitHubRelease.checksum(inBody: String(repeating: "a", count: 128)) == nil)
        #expect(GitHubRelease.checksum(inBody: String(repeating: "a", count: 63)) == nil)
    }
}

@Suite("Когда проверять обновления")
struct UpdateScheduleTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func check(last: Date?, enabled: Bool = true, manual: Bool = false) -> Bool {
        UpdateSchedule.shouldCheck(now: now, last: last, enabled: enabled, manual: manual)
    }

    @Test("Не проверявшись ни разу — проверяем")
    func первыйРаз() {
        #expect(check(last: nil))
    }

    @Test("Ровно сутки — уже пора, без пяти минут — ещё нет")
    func граница() {
        #expect(check(last: now.addingTimeInterval(-UpdateSchedule.interval)))
        #expect(!check(last: now.addingTimeInterval(-UpdateSchedule.interval + 300)))
    }

    /// Единственный смысл кнопки «Проверить» — сходить сейчас. Она обязана
    /// работать и тогда, когда автопроверка выключена.
    @Test("Нажатие рукой проверяет всегда")
    func рукойВсегда() {
        #expect(check(last: now, manual: true))
        #expect(check(last: now, enabled: false, manual: true))
    }

    @Test("С выключенной автопроверкой сама не ходит")
    func выключено() {
        #expect(!check(last: nil, enabled: false))
    }

    /// Часы перевели назад или сменили пояс — и последняя проверка оказалась
    /// в будущем. Без этой ветки проверка залипла бы, пока будущее не наступит.
    @Test("Дата из будущего не запирает проверку на месяцы")
    func датаИзБудущего() {
        #expect(check(last: now.addingTimeInterval(30 * 24 * 3600)))
    }
}

@Suite("Куда ставить обновление")
struct UpdateInstallerTests {
    private func target(_ path: String, writable: Bool = true) -> InstallTarget {
        UpdateInstaller.target(bundleURL: URL(fileURLWithPath: path), parentIsWritable: writable)
    }

    @Test("Обычная установка в «Программы» годится")
    func обычнаяУстановка() {
        #expect(target("/Applications/Trunook.app") == .ready(URL(fileURLWithPath: "/Applications/Trunook.app")))
    }

    /// Ставим туда, откуда работаем, а не в зашитую «/Applications»:
    /// приложение может лежать где угодно, в том числе в домашней папке.
    @Test("Ставим туда, откуда работаем")
    func ставимОткудаРаботаем() {
        let home = "/Users/кто-то/Applications/Trunook.app"
        #expect(target(home) == .ready(URL(fileURLWithPath: home)))
    }

    /// Запуск прямо с образа или из карантина переноса: этой копии всё равно
    /// не жить, подменять там нечего.
    @Test("С образа и из карантина переноса ставить нечего")
    func сОбразаНеСтавим() {
        #expect(target("/Volumes/Trunook 0.12.0/Trunook.app") == .refused(.notInstalled))
        #expect(target("/private/var/folders/x/AppTranslocation/ABC/d/Trunook.app") == .refused(.notInstalled))
    }

    /// Пароль не просим никогда: установщик от root опаснее той беды,
    /// которую решал бы.
    @Test("Без права на запись — отказ, а не запрос пароля")
    func безПраваОтказ() {
        #expect(target("/Applications/Trunook.app", writable: false) == .refused(.notWritable))
    }
}

@Suite("Образ с обновлением")
struct DiskImageTests {
    /// Записанный ответ настоящего `hdiutil attach -plist` на выпущенном
    /// образе 0.11.1. Живьём это не проверить в тесте: монтирование —
    /// действие над системой, а не расчёт.
    private func plist(_ entities: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>system-entities</key><array>
        \(entities)
        </array></dict></plist>
        """.utf8)
    }

    private let volume = """
    <dict><key>content-hint</key><string>Apple_HFS</string>
    <key>dev-entry</key><string>/dev/disk4s1</string>
    <key>mount-point</key><string>/private/tmp/dmg.f3KfGl</string>
    <key>potentially-mountable</key><true/></dict>
    """

    private let scheme = """
    <dict><key>content-hint</key><string>GUID_partition_scheme</string>
    <key>dev-entry</key><string>/dev/disk4</string>
    <key>potentially-mountable</key><false/></dict>
    """

    @Test("Точка монтирования и устройство читаются из ответа")
    func точкаЧитается() throws {
        let image = try #require(DiskImage.mounted(fromPlist: plist(volume + scheme)))
        #expect(image.mountPoint.path == "/private/tmp/dmg.f3KfGl")
        #expect(image.device == "/dev/disk4s1")
    }

    /// Порядок записей `hdiutil` не обещает, а у схемы разделов точки
    /// монтирования нет вовсе. Брать первую запись подряд нельзя.
    @Test("Схема разделов перед томом не сбивает разбор")
    func схемаПередТомом() throws {
        let image = try #require(DiskImage.mounted(fromPlist: plist(scheme + volume)))
        #expect(image.mountPoint.path == "/private/tmp/dmg.f3KfGl")
    }

    @Test("Ответ без единого тома ничего не даёт")
    func безТома() {
        #expect(DiskImage.mounted(fromPlist: plist(scheme)) == nil)
        #expect(DiskImage.mounted(fromPlist: Data("не plist вовсе".utf8)) == nil)
    }
}

@Suite("Подпись обновления")
struct CodeSignatureCheckTests {
    /// Сам вызов Security.framework тестом не проверить — нужен подписанный
    /// бандл и живая служба. Проверяется разбор ответа: он решает, что человек
    /// увидит и можно ли пробовать снова.
    @Test("Успех означает годную подпись")
    func успех() {
        #expect(CodeSignatureCheck.verdict(for: errSecSuccess) == .valid)
    }

    /// Два отказа различаются нарочно. «Не подписано» — это подмена образа.
    /// «Другой сертификат» — то, что однажды случится законно, когда
    /// сертификат перевыпустят, и человеку надо сказать разное.
    @Test("Отсутствие подписи и чужой сертификат — разные отказы")
    func дваОтказа() {
        #expect(CodeSignatureCheck.verdict(for: errSecCSUnsigned) == .rejected(.unsigned))
        #expect(CodeSignatureCheck.verdict(for: errSecCSReqFailed) == .rejected(.wrongCertificate))
    }

    /// Неизвестный код — не повод пропустить обновление внутрь. Всё, что
    /// не разобрано, считается порчей.
    @Test("Незнакомый код считается порчей, а не удачей")
    func незнакомыйКод() {
        #expect(CodeSignatureCheck.verdict(for: errSecCSSignatureFailed) == .rejected(.damaged))
        #expect(CodeSignatureCheck.verdict(for: errSecCSResourcesInvalid) == .rejected(.damaged))
        #expect(CodeSignatureCheck.verdict(for: -12345) == .rejected(.damaged))
    }
}

@Suite("Строка состояния обновления")
struct UpdateStatusTextTests {
    private func release() throws -> GitHubRelease {
        try #require(GitHubRelease.parse(Data("""
        {"tag_name":"v0.12.0","assets":[{"name":"a.dmg","size":1,
          "browser_download_url":"https://example.com/a.dmg"}]}
        """.utf8)))
    }

    /// Текст и кнопка приходят из одного места нарочно: «Готово к установке»
    /// с кнопкой «Проверить» — это не опечатка, а обещание, которого
    /// приложение не выполнит.
    @Test("Готовому обновлению отвечает кнопка установки")
    func готовоеСтавится() throws {
        let line = UpdateStatusText.line(
            for: .ready(try release(), staged: URL(fileURLWithPath: "/tmp/Trunook.app"))
        )
        #expect(line.action == .install)
        #expect(line.text.contains("0.12.0"))
    }

    @Test("Пока идёт работа, кнопка выключена")
    func вРаботеКнопкаВыключена() throws {
        #expect(UpdateStatusText.line(for: .checking).action == .busy)
        #expect(UpdateStatusText.line(for: .installing).action == .busy)
        #expect(UpdateStatusText.line(for: .downloading(try release(), progress: 0.42)).action == .busy)
    }

    @Test("Доля загрузки показывается процентами")
    func доляПроцентами() throws {
        let line = UpdateStatusText.line(for: .downloading(try release(), progress: 0.42))
        #expect(line.text.contains("42"))
    }

    /// После отказа предлагается повтор, а не установка: ставить нечего.
    @Test("После отказа предлагается повторить проверку")
    func отказПовторяется() {
        let line = UpdateStatusText.line(for: .failed(.network))
        #expect(line.action == .check)
        #expect(!line.text.isEmpty)
    }

    @Test("У каждой причины отказа есть текст")
    func уКаждойПричиныЕстьТекст() {
        let reasons: [UpdateFailure] = [
            .network, .rateLimited, .badResponse, .checksumMismatch, .unsigned,
            .wrongCertificate, .damaged, .notWritable, .notInstalled, .noSpace, .installFailed
        ]
        for reason in reasons {
            #expect(!reason.message.isEmpty)
        }
    }
}
