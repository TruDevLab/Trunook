import AppKit
import Foundation
import Testing
@testable import Trunook

@Suite("Разговор с моделью: две разметки одного потока")
struct ModelClientTests {
    // MARK: - Ollama

    @Test("Кусок ответа Ollama берётся из message.content")
    func ollamaToken() {
        let line = #"{"model":"gemma3:4b","message":{"role":"assistant","content":"Привет"},"done":false}"#
        #expect(ModelClient.token(in: line, dialect: .ollama) == "Привет")
        #expect(ModelClient.isEnd(line, dialect: .ollama) == false)
    }

    @Test("Ollama сообщает о конце потока полем done")
    func ollamaEnd() {
        let line = #"{"model":"gemma3:4b","message":{"role":"assistant","content":""},"done":true}"#
        #expect(ModelClient.isEnd(line, dialect: .ollama))
    }

    // MARK: - Совместимый с OpenAI

    @Test("Кусок ответа берётся из choices[0].delta.content")
    func openAIToken() {
        let line = #"data: {"choices":[{"index":0,"delta":{"content":"Привет"}}]}"#
        #expect(ModelClient.token(in: line, dialect: .openAI) == "Привет")
    }

    @Test("Первая посылка несёт роль без текста — читать нечего")
    func openAIRoleOnly() {
        let line = #"data: {"choices":[{"index":0,"delta":{"role":"assistant"}}]}"#
        #expect(ModelClient.token(in: line, dialect: .openAI) == nil)
    }

    @Test("Конец потока — отдельной строкой [DONE]")
    func openAIEnd() {
        #expect(ModelClient.isEnd("data: [DONE]", dialect: .openAI))
        #expect(ModelClient.token(in: "data: [DONE]", dialect: .openAI) == nil)
    }

    @Test("Пустые разделители и служебные строки пропускаются молча")
    func openAINoise() {
        // Поток SSE разделяет посылки пустой строкой, а иные серверы
        // добавляют `event:` и комментарии. Ни одна из этих строк
        // не является ни ответом, ни концом.
        for line in ["", ":ping", "event: message"] {
            #expect(ModelClient.token(in: line, dialect: .openAI) == nil)
            #expect(ModelClient.isEnd(line, dialect: .openAI) == false)
        }
    }

    // MARK: - Список моделей

    @Test("Ollama перечисляет модели именами в models[].name")
    func ollamaModels() {
        let data = Data(#"{"models":[{"name":"gemma3:4b"},{"name":"qwen3:8b"}]}"#.utf8)
        #expect(ModelClient.models(in: data, dialect: .ollama).map(\.name) == ["gemma3:4b", "qwen3:8b"])
    }

    @Test("Совместимый сервер перечисляет их в data[].id")
    func openAIModels() {
        let data = Data(#"{"object":"list","data":[{"id":"gpt-oss-20b","object":"model"}]}"#.utf8)
        #expect(ModelClient.models(in: data, dialect: .openAI).map(\.name) == ["gpt-oss-20b"])
    }

    @Test("Чужая разметка списка не роняет разбор, а даёт пустой список")
    func wrongShapeIsEmpty() {
        // Ошибиться провайдером легко — адрес один, а отвечают по-разному.
        // Пустой список честнее выдумки: он и показывается как «сервер
        // не отвечает или моделей нет».
        let ollama = Data(#"{"models":[{"name":"gemma3:4b"}]}"#.utf8)
        #expect(ModelClient.models(in: ollama, dialect: .openAI).isEmpty)
        #expect(ModelClient.models(in: Data("не json".utf8), dialect: .ollama).isEmpty)
    }

    // MARK: - Преднастройки

    @Test("Диалект у Ollama свой, у остальных общий")
    func dialects() {
        #expect(AIProvider.ollama.dialect == .ollama)
        for provider in AIProvider.allCases where provider != .ollama {
            #expect(provider.dialect == .openAI, "\(provider.title)")
        }
    }

    @Test("У каждой преднастройки есть адрес, у кастомной его нет")
    func presetsHaveURLs() {
        // Преднастройка без адреса — пустое поле и молчащий сервер: человек
        // выбрал провайдера и не понимает, почему ничего не работает.
        for provider in AIProvider.allCases where provider != .custom && provider != .ollama {
            let url = provider.presetURL
            #expect(url != nil, "\(provider.title) без адреса")
            #expect(url?.hasPrefix("http") == true, "\(provider.title): \(url ?? "—")")
        }
        #expect(AIProvider.custom.presetURL == nil)
        // У Ollama адрес свой, не из этого поля: у неё и путь другой.
        #expect(AIProvider.ollama.presetURL == nil)
    }

    @Test("Местное не считается уходящим в интернет")
    func localIsNotRemote() {
        for provider in AIProvider.local { #expect(!provider.isRemote, "\(provider.title)") }
        for provider in AIProvider.cloud { #expect(provider.isRemote, "\(provider.title)") }
        // Кастомный не предупреждает: куда он ведёт, знает только человек,
        // а пугать его собственным localhost незачем.
        #expect(!AIProvider.custom.isRemote)
    }

    @Test("Списки провайдеров вместе покрывают все случаи")
    func listsCoverEverything() {
        // Пункт, не попавший ни в один раздел, просто исчезает из меню.
        let listed = Set(AIProvider.local + AIProvider.cloud + [.custom])
        #expect(listed == Set(AIProvider.allCases))
    }

    @Test("Ключ спрашивается у всех, кроме Ollama")
    func keyIsAskedWhereItCanBeNeeded() {
        // Местные серверы запускают и с ключом тоже: поле, спрятанное
        // по догадке о чужой настройке, оставило бы человека без места,
        // куда его вписать.
        #expect(!AIProvider.ollama.usesKey)
        for provider in AIProvider.allCases where provider != .ollama {
            #expect(provider.usesKey, "\(provider.title)")
        }
    }

    // MARK: - Модель вместе с её сервером

    @Test("Имя складывается с провайдером и разбирается обратно")
    func refRoundTrip() {
        let ref = ModelRef(provider: .groq, name: "llama-3.3-70b")
        #expect(ref.stored == "groq|llama-3.3-70b")
        #expect(ModelRef.parse(ref.stored, fallback: .ollama) == ref)
    }

    @Test("Косая черта в имени модели разбор не путает")
    func slashesSurvive() {
        // Именно так называются модели у Unsloth и с Hugging Face —
        // разделителем поэтому взята вертикальная черта, а не косая.
        for name in ["unsloth/gemma-4-E4B-it-qat-GGUF", "hf.co/Qwen/Qwen3-Embedding-4B-GGUF:Q4_K_M"] {
            let ref = ModelRef(provider: .unsloth, name: name)
            #expect(ModelRef.parse(ref.stored, fallback: .ollama) == ref)
        }
    }

    @Test("Голое имя достаётся основному провайдеру")
    func bareNameFallsBack() {
        // Так лежат имена, сохранённые до того, как провайдеров стало
        // несколько. Читаются они как принадлежащие основному — и при первой
        // же загрузке команд переписываются набело.
        #expect(ModelRef.parse("gemma3:4b", fallback: .ollama)
            == ModelRef(provider: .ollama, name: "gemma3:4b"))
    }

    @Test("Неизвестный провайдер в имени не съедает само имя")
    func unknownProviderKeepsName() {
        // Провайдера могли переименовать между версиями. Потерять при этом
        // имя модели значит молча оставить команду без модели вовсе.
        let ref = ModelRef.parse("небылоТакого|gpt-4o", fallback: .openAI)
        #expect(ref == ModelRef(provider: .openAI, name: "небылоТакого|gpt-4o"))
    }

    @Test("Пустое имя моделью не является")
    func emptyIsNil() {
        #expect(ModelRef.parse("", fallback: .ollama) == nil)
    }

    @Test("Приставка library/ в показе не участвует")
    func shortNameDropsLibrary() {
        #expect(ModelRef(provider: .ollama, name: "library/gemma3:4b").shortName == "gemma3:4b")
    }
}

@Suite("Провайдеров держат несколько")
struct ProviderSettingsTests {
    private func fresh() -> Settings {
        let name = "trunook.tests." + UUID().uuidString
        return Settings(defaults: UserDefaults(suiteName: name)!)
    }

    @Test("Ключ и адрес у каждого провайдера свои")
    func keysDoNotLeakBetweenProviders() {
        // Общими они были одну версию, и этого хватило: ключ от прежнего
        // провайдера оставался в поле нового, уходил с запросом и получал
        // отказ, в котором виноватым выглядел новый сервер.
        let settings = fresh()
        settings.setAPIKey("ключ-groq", for: .groq)
        settings.setAPIURL("http://свой:1234/v1", for: .lmStudio)

        #expect(settings.apiKey(for: .groq) == "ключ-groq")
        #expect(settings.apiKey(for: .openAI).isEmpty)
        #expect(settings.apiURLRaw(for: .groq).isEmpty)
        #expect(settings.apiURL(for: .groq) == AIProvider.groq.presetURL)
        #expect(settings.apiURL(for: .lmStudio) == "http://свой:1234/v1")
    }

    @Test("Основной провайдер включается сам")
    func mainProviderIsAlwaysEnabled() {
        let settings = fresh()
        settings.enabledProviders = [.ollama]
        settings.aiProvider = .groq
        #expect(settings.isProviderEnabled(.groq))
        #expect(settings.enabledProviders.contains(.ollama))
    }

    @Test("Основного не выключить")
    func mainProviderCannotBeRemoved() {
        // Выключенный основной означал бы, что вопрос уходит туда, где его
        // никто не ждёт, — и понять это по экрану было бы нельзя.
        let settings = fresh()
        settings.aiProvider = .ollama
        settings.setProvider(.ollama, enabled: false)
        #expect(settings.isProviderEnabled(.ollama))
    }

    @Test("Выключение убирает только названного")
    func removingKeepsTheRest() {
        let settings = fresh()
        settings.aiProvider = .ollama
        settings.setProvider(.groq, enabled: true)
        settings.setProvider(.lmStudio, enabled: true)
        settings.setProvider(.groq, enabled: false)

        #expect(settings.enabledProviders == [.ollama, .lmStudio])
    }

    @Test("Порядок включённых не зависит от порядка включения")
    func orderIsStable() {
        // Список, меняющий порядок от правки к правке, читается как другой
        // список — и в настройках, и в выборе модели у команды.
        let settings = fresh()
        settings.aiProvider = .groq
        settings.setProvider(.ollama, enabled: true)
        #expect(settings.enabledProviders == AIProvider.allCases.filter {
            $0 == .ollama || $0 == .groq
        })
    }

    @Test("Старые настройки переезжают к тому, кто был выбран")
    func migrationMovesOldFields() {
        let name = "trunook.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.set("unsloth", forKey: "aiProvider")
        defaults.set("http://127.0.0.1:8888/v1", forKey: "apiURL")
        defaults.set("секрет", forKey: "apiKey")
        defaults.set("gemma-4", forKey: "apiModel")
        defaults.set("http://localhost:11434", forKey: "ollamaURL")
        defaults.set("gemma3:4b", forKey: "ollamaModel")

        let settings = Settings(defaults: defaults)
        settings.migrateProviderSettings()

        #expect(settings.apiKey(for: .unsloth) == "секрет")
        #expect(settings.apiModel(for: .unsloth) == "gemma-4")
        #expect(settings.apiModel(for: .ollama) == "gemma3:4b")
        #expect(settings.apiURLRaw(for: .ollama) == "http://localhost:11434")
        #expect(settings.enabledProviders == [.unsloth])
        // Ключ не расползается: он принадлежал одному провайдеру и остаётся
        // у него.
        #expect(settings.apiKey(for: .ollama).isEmpty)
    }

    @Test("Ключ ничьих полей достаётся тому, чей это адрес")
    func migrationFindsOwnerByURL() {
        // Человек настроил чужой сервер, а потом вернулся к Ollama: общие
        // поля остались лежать, и выбранный провайдер про них ничего
        // не говорит. Хозяина узнаём по адресу.
        let name = "trunook.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.set("ollama", forKey: "aiProvider")
        defaults.set(AIProvider.groq.presetURL, forKey: "apiURL")
        defaults.set("секрет", forKey: "apiKey")

        let settings = Settings(defaults: defaults)
        settings.migrateProviderSettings()

        #expect(settings.apiKey(for: .groq) == "секрет")
        #expect(settings.isProviderEnabled(.groq))
        #expect(settings.aiProvider == .ollama)
    }

    @Test("Ключ без узнаваемого адреса не пропадает")
    func migrationKeepsUnattributableKey() {
        // Заново его взять неоткуда — а «кастомный провайдер» и есть место,
        // где такому ключу видно и откуда его можно переставить.
        let name = "trunook.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.set("ollama", forKey: "aiProvider")
        defaults.set("секрет", forKey: "apiKey")

        let settings = Settings(defaults: defaults)
        settings.migrateProviderSettings()

        #expect(settings.apiKey(for: .custom) == "секрет")
        #expect(settings.isProviderEnabled(.custom))
    }

    @Test("Старая копия ключа не остаётся лежать")
    func migrationClearsLegacyFields() {
        // Секрет, лежащий там, где его больше никто не читает, никто
        // и не сотрёт.
        let name = "trunook.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.set("groq", forKey: "aiProvider")
        defaults.set("секрет", forKey: "apiKey")

        Settings(defaults: defaults).migrateProviderSettings()

        #expect(defaults.string(forKey: "apiKey") == nil)
    }

    @Test("Перенос делается однажды")
    func migrationRunsOnce() {
        let name = "trunook.tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.set("groq", forKey: "aiProvider")
        defaults.set("старый", forKey: "apiKey")

        let settings = Settings(defaults: defaults)
        settings.migrateProviderSettings()
        settings.setAPIKey("новый", for: .groq)
        defaults.set("старый", forKey: "apiKey")
        settings.migrateProviderSettings()

        // Повторный перенос затёр бы поправленное человеком.
        #expect(settings.apiKey(for: .groq) == "новый")
    }
}

@Suite("Полоска горящей чашки")
struct CaffeineChipTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("Без срока вместо цифр стоит знак бесконечности")
    func endlessShowsSign() {
        #expect(CaffeineChipView.label(endsAt: nil, now: now) == CaffeineChipView.endless)
    }

    @Test("Остаток показывается временем")
    func remainingIsClock() {
        #expect(CaffeineChipView.label(endsAt: now.addingTimeInterval(90 * 60), now: now) == "1:30:00")
        #expect(CaffeineChipView.label(endsAt: now.addingTimeInterval(65), now: now) == "01:05")
    }

    @Test("Последняя секунда ещё не кончилась")
    func lastSecondIsNotZero() {
        // Округление вниз показывало бы «0:00» на живой чашке — то есть
        // «уже кончилось» там, где ещё держим.
        #expect(CaffeineChipView.label(endsAt: now.addingTimeInterval(0.4), now: now) == "00:01")
    }

    @Test("Вышедший срок показывается нулём, а не отрицательным")
    func expiredIsZero() {
        #expect(CaffeineChipView.label(endsAt: now.addingTimeInterval(-30), now: now) == "00:00")
    }
}

@Suite("Значки провайдеров")
struct ProviderMarkTests {
    @Test("Марка есть у каждого и она не пустая")
    func everyProviderHasAMark() {
        // Пустая марка — это пустое место в строке команды: имени
        // провайдера там нет, весь ответ на «чьё это» несёт значок.
        for provider in AIProvider.allCases {
            let mark = ProviderMark.image(for: provider, size: 12)
            #expect(mark.size.width == 12, "\(provider.title)")
            #expect(mark.isTemplate, "\(provider.title)")
        }
    }

    @Test("Марки у разных провайдеров разные")
    func marksDiffer() {
        // Две одинаковые означали бы, что различить провайдеров в строке
        // нельзя вовсе. Сверяем сами пиксели: два разных рисунка могут
        // случайно совпасть только если это один и тот же рисунок.
        var seen: [Data] = []
        for provider in AIProvider.allCases {
            let mark = ProviderMark.image(for: provider, size: 48)
            guard let data = mark.tiffRepresentation else {
                Issue.record("нет картинки у \(provider.title)")
                continue
            }
            #expect(!seen.contains(data), "марка \(provider.title) повторяет чужую")
            seen.append(data)
        }
    }

    @Test("Марка не пустая: в квадрате есть закрашенные точки")
    func marksAreNotBlank() {
        // Кривая, ушедшая за пределы квадрата, дала бы пустой прозрачный
        // значок — и по снимку панели это выглядело бы как «значка нет».
        for provider in AIProvider.allCases {
            let mark = ProviderMark.image(for: provider, size: 48)
            guard let data = mark.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: data)
            else {
                Issue.record("нет растра у \(provider.title)")
                continue
            }
            var painted = 0
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
                    if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { painted += 1 }
                }
            }
            #expect(painted > 20, "марка \(provider.title) почти пуста")
        }
    }
}
