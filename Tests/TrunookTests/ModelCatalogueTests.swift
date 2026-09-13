import Foundation
import Testing
@testable import Trunook

/// Каталог моделей: что предлагаем и что советуем этой машине.
///
/// Совет считается по памяти и свободному месту, и проверять его надо
/// на выдуманных числах, а не на той технике, где случилось запустить
/// прогон: иначе тест зелёный у разработчика и красный у всех остальных.
@Suite("Каталог моделей")
struct ModelCatalogueTests {
    private let гигабайт: Int64 = 1_000_000_000

    private func машина(памяти: Int64, диска: Int64 = 500) -> MachineResources {
        MachineResources(ram: памяти * гигабайт, freeDisk: диска * гигабайт)
    }

    private var машинаПользователя: MachineResources { машина(памяти: 24) }

    // MARK: - Совет по ресурсам

    @Test("Чем больше памяти, тем тяжелее советуемая модель")
    func советРастётСПамятью() {
        #expect(ModelCatalogue.recommended(on: машина(памяти: 8)).tag == "qwen3:4b-instruct")
        #expect(ModelCatalogue.recommended(on: машина(памяти: 16)).tag == "qwen3:8b")
        #expect(ModelCatalogue.recommended(on: машина(памяти: 24)).tag == "qwen3:8b")
        #expect(ModelCatalogue.recommended(on: машина(памяти: 32)).tag == "gpt-oss:20b")
        #expect(ModelCatalogue.recommended(on: машина(памяти: 64)).tag == "gpt-oss:20b")
    }

    /// Советовать нечего — но пустое место на экране хуже, чем лёгкая
    /// модель с названной недостачей: у человека должна быть цифра.
    @Test("Машине слабее всех разрядов советуется лёгкая, с недостачей")
    func слабаяМашинаПолучаетЛёгкую() {
        let слабая = машина(памяти: 4)
        let совет = ModelCatalogue.recommended(on: слабая)
        #expect(совет.tag == "qwen3:4b-instruct")
        #expect(ModelCatalogue.fit(совет, on: слабая) == .needsRAM(4 * гигабайт))
    }

    /// В день, когда совет и значение по умолчанию разойдутся, приложение
    /// будет советовать одну модель, а спрашивать другую — и человек
    /// получит «модели нет» на первом же вопросе.
    @Test("Совет для этой машины совпадает с моделью по умолчанию")
    func советСовпадаетСУмолчанием() {
        #expect(ModelCatalogue.recommended(on: машина(памяти: 24)).tag == RecommendedModel.chat)
    }

    // MARK: - Место на диске

    @Test("Мощная модель не советуется, когда на диске тесно")
    func тесныйДискОпускаетСовет() {
        // Памяти на мощную хватает, а места нет: 13,8 ГБ плюс запас
        // в 3 ГБ не влезают в 10 ГБ свободных.
        let тесная = машина(памяти: 64, диска: 10)
        #expect(ModelCatalogue.recommended(on: тесная).tag == "qwen3:8b")
    }

    @Test("Запас на диске считается сверх веса модели")
    func запасУчитывается() throws {
        let мощная = try #require(ModelCatalogue.chat.first { $0.tier == .powerful })

        // Ровно вес модели, без запаса: не влезает.
        let вплотную = MachineResources(ram: 64 * гигабайт, freeDisk: мощная.bytes)
        #expect(ModelCatalogue.fit(мощная, on: вплотную) == .needsDisk(ModelCatalogue.diskReserve))

        let сЗапасом = MachineResources(
            ram: 64 * гигабайт,
            freeDisk: мощная.bytes + ModelCatalogue.diskReserve
        )
        #expect(ModelCatalogue.fit(мощная, on: сЗапасом) == .fits)
    }

    /// Память проверяется раньше диска: место освобождают за минуту,
    /// а память не добавишь, и говорить надо про то, что не лечится.
    @Test("Не хватает и памяти, и места — говорим про память")
    func памятьВажнееДиска() {
        let никакая = машина(памяти: 4, диска: 1)
        let лёгкая = ModelCatalogue.chat[0]
        guard case .needsRAM = ModelCatalogue.fit(лёгкая, on: никакая) else {
            Issue.record("ждали нехватку памяти, а не места")
            return
        }
    }

    // MARK: - Состав каталога

    @Test("Разговорных разрядов три, векторная модель одна")
    func составКаталога() {
        #expect(ModelCatalogue.chat.count == 3)
        #expect(ModelCatalogue.offers.filter { $0.role == .embed }.count == 1)
        #expect(ModelCatalogue.embed.tag == RecommendedModel.embed)
    }

    @Test("Теги не повторяются")
    func тегиУникальны() {
        let теги = ModelCatalogue.offers.map(\.tag)
        #expect(Set(теги).count == теги.count)
    }

    /// Вес и требование к памяти обязаны расти вместе: разряд, который
    /// весит больше соседнего, но требует меньше, — опечатка в таблице.
    @Test("Разряды идут по возрастанию веса и требований")
    func разрядыВозрастают() {
        let разговорные = ModelCatalogue.chat
        for (младший, старший) in zip(разговорные, разговорные.dropFirst()) {
            #expect(младший.tier < старший.tier)
            #expect(младший.bytes < старший.bytes)
            #expect(младший.minRAM < старший.minRAM)
        }
    }

    /// Памяти нужно вдвое против веса: модель обязана уместиться рядом
    /// с работой человека, а не впритык.
    @Test("Требование к памяти — не меньше двух весов")
    func памятиВдвоеБольшеВеса() {
        for предложение in ModelCatalogue.chat {
            #expect(предложение.minRAM >= предложение.bytes * 2)
        }
    }

    @Test("Каждое предложение подписано и показывает вес")
    func предложенияПодписаны() {
        for предложение in ModelCatalogue.offers {
            #expect(!предложение.title.isEmpty)
            #expect(!предложение.detail.isEmpty)
            #expect(!предложение.sizeText.isEmpty)
        }
    }

    // MARK: - Строки списка

    private func строки(
        installed: [String] = [],
        selected: String = "",
        installing: String? = nil,
        share: Double = 0,
        queued: [String] = []
    ) -> [ModelOfferRow] {
        ModelCatalogue.rows(
            on: машинаПользователя,
            installed: installed.map { ModelRef(provider: .ollama, name: $0) },
            selected: selected,
            installing: installing,
            share: share,
            queued: queued
        )
    }

    private func строка(_ tag: String, _ все: [ModelOfferRow]) throws -> ModelOfferRow {
        try #require(все.first { $0.offer.tag == tag })
    }

    @Test("Советуемая модель помечена, непосильная приглушена")
    func пометкиНаЧистойМашине() throws {
        let все = строки()
        #expect(try строка("qwen3:8b", все).badge == .recommended)
        #expect(try строка("qwen3:8b", все).action == .install)

        // 24 ГБ для мощной мало: нажимать нечего, и сказано, сколько нужно.
        let мощная = try строка("gpt-oss:20b", все)
        #expect(мощная.badge == .heavy)
        #expect(мощная.action == .blocked)
        #expect(мощная.warning != nil)
    }

    @Test("Скачанную можно выбрать, выбранной делать нечего")
    func выборСкачанной() throws {
        let все = строки(installed: ["qwen3:4b-instruct", "qwen3:8b"], selected: "qwen3:8b")
        #expect(try строка("qwen3:8b", все).badge == .selected)
        #expect(try строка("qwen3:8b", все).action == .none)
        #expect(try строка("qwen3:4b-instruct", все).badge == .installed)
        #expect(try строка("qwen3:4b-instruct", все).action == .select)
    }

    /// Поймано на живой машине: `gpt-oss:20b` у пользователя скачана
    /// и работает, а 24 ГБ памяти нашему порогу в 32 не отвечают — и строка
    /// с рабочей моделью гасла. Порог нужен, чтобы советовать, а не чтобы
    /// спорить с тем, что уже работает.
    @Test("Скачанная модель не приглушается, даже если порог не сошёлся")
    func скачаннаяНеГаснет() throws {
        let все = строки(installed: ["gpt-oss:20b"])
        let мощная = try строка("gpt-oss:20b", все)
        #expect(мощная.badge == .installed)
        #expect(мощная.action == .select)
        // И не спорим с тем, что человек уже делает: «нужно 32 ГБ памяти»
        // у работающей модели на машине с 24 — неправда о её же опыте.
        #expect(мощная.warning == nil)
    }

    /// Скачанность видна по кнопке «Отвечать ею», а совет — единственное,
    /// что человеку здесь подсказывают. На машине, где скачано всё, совет
    /// иначе не показывался вовсе.
    @Test("Совет виден и у скачанной модели")
    func советВидноУСкачанной() throws {
        let все = строки(installed: ["qwen3:4b-instruct", "qwen3:8b"], selected: "qwen3:4b-instruct")
        #expect(try строка("qwen3:8b", все).badge == .recommended)
        #expect(try строка("qwen3:8b", все).action == .select)
        #expect(try строка("qwen3:4b-instruct", все).badge == .selected)
    }

    /// Ollama зовёт скачанное `nomic-embed-text:latest`, а просят её без
    /// метки. Точное сравнение отвечало бы «не установлена» на скачанную.
    @Test("Метка :latest сравнению не мешает")
    func меткаНеМешает() throws {
        let все = строки(installed: ["nomic-embed-text:latest"])
        let векторная = try строка(RecommendedModel.embed, все)
        #expect(векторная.badge == .installed)
        // Выбирать векторную негде: её имя живёт отдельной настройкой.
        #expect(векторная.action == .none)
    }

    @Test("Полоса горит только у качающейся строки")
    func полосаТолькоУСвоей() throws {
        let все = строки(installing: "qwen3:8b", share: 0.4, queued: [RecommendedModel.embed])
        #expect(try строка("qwen3:8b", все).action == .installing(0.4))
        #expect(try строка(RecommendedModel.embed, все).action == .queued)
        #expect(try строка("qwen3:4b-instruct", все).action == .install)
    }

    // MARK: - Просьба не рассуждать

    /// Поле `think` есть только у Ollama. Строгий OpenAI-совместимый сервер
    /// на лишнее поле отвечает отказом — то есть перестал бы отвечать вовсе.
    @Test("Без раздумий просим только у Ollama")
    func безРаздумийТолькоУOllama() {
        #expect(ModelClient.skipsThinking(fast: true, model: "gemma4:12b", dialect: .ollama))
        #expect(!ModelClient.skipsThinking(fast: true, model: "gemma4:12b", dialect: .openAI))
        #expect(!ModelClient.skipsThinking(fast: false, model: "gemma4:12b", dialect: .ollama))
        // Даже модель каталога без раздумий не получает поля у чужого
        // диалекта: строгий сервер ответил бы отказом.
        #expect(!ModelClient.skipsThinking(fast: false, model: "qwen3:8b", dialect: .openAI))
    }

    /// Средняя отвечает без раздумий сама, что бы ни стояло в выключателе:
    /// круг за две секунды вместо тринадцати при тех же вызовах. Лёгкой
    /// признак не нужен — она не думает и так, мощной вреден — без раздумий
    /// она медленнее.
    @Test("Средняя модель каталога отвечает без раздумий сама")
    func средняяБезРаздумий() throws {
        let средняя = try #require(ModelCatalogue.chat.first { $0.tier == .medium })
        #expect(средняя.skipsThinking)
        #expect(ModelCatalogue.answersWithoutThinking(средняя.tag))
        #expect(ModelClient.skipsThinking(fast: false, model: средняя.tag, dialect: .ollama))

        #expect(!ModelCatalogue.answersWithoutThinking("gpt-oss:20b"))
        #expect(!ModelCatalogue.answersWithoutThinking("qwen3:4b-instruct"))
        // Сравнение с меткой: признак средней не переходит на соседей по семейству.
        #expect(!ModelCatalogue.answersWithoutThinking("qwen3:4b"))
    }

    @Test("Самая лёгкая — разряд «Лёгкая»")
    func самаяЛёгкая() {
        #expect(ModelCatalogue.lightest.tier == .light)
        #expect(ModelCatalogue.lightest.tag == "qwen3:4b-instruct")
    }

    @Test("Пара для одной кнопки — разговорная, потом векторная")
    func параПоПорядку() {
        let пара = ModelCatalogue.recommendedPair(on: машинаПользователя)
        #expect(пара == [RecommendedModel.chat, RecommendedModel.embed])
    }
}
