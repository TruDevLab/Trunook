import Foundation

/// Предложение скачать модель: что это за модель, сколько весит и какой
/// машине по силам.
///
/// Человек не обязан знать ни слова «квантизация», ни того, что `qwen3:8b` —
/// это восемь миллиардов параметров. Он обязан понять одно: какая из трёх
/// подойдёт его компьютеру. Поэтому у предложения есть разряд и вес,
/// а не список свойств.
struct ModelOffer: Equatable, Identifiable {
    /// Зачем модель нужна. Их две породы, и они несравнимы: первая отвечает
    /// словами, вторая считает векторы смысла и текстом не отвечает вовсе.
    enum Role: Equatable {
        case chat
        case embed
    }

    /// Насколько модель тяжёлая. Порядок разрядов — порядок показа.
    enum Tier: Int, Equatable, Comparable {
        case light = 0
        case medium = 1
        case powerful = 2
        /// У векторной модели разряда нет: выбирать не из чего.
        case none = 3

        static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Имя для `/api/pull` — оно же имя, которым модель зовут в запросе.
    let tag: String
    let role: Role
    let tier: Tier
    /// Вес скачивания в байтах. Десятичные, как считает сама macOS.
    let bytes: Int64
    /// Сколько памяти должно быть **на машине**, а не в модели. Почему
    /// не вес — в комментарии к `ModelCatalogue.fit`.
    let minRAM: Int64
    /// Отвечать без раздумий, что бы ни стояло в общем выключателе.
    ///
    /// Каталог знает свои модели лучше человека: он их замерял. У `qwen3:8b`
    /// раздумья стоили десяти секунд на круг помощника и не давали ни одного
    /// верного вызова сверх того, что она делает без них. У других разрядов
    /// признака нет: `qwen3:4b-instruct` не думает и так, а `gpt-oss:20b`
    /// без раздумий, наоборот, медленнее.
    var skipsThinking = false

    var id: String { tag }

    /// «Средняя», «Мощная» — то, что человек читает первым.
    var title: String {
        switch role {
        case .embed:
            return t("Для заметок")
        case .chat:
            switch tier {
            case .light: return t("Лёгкая")
            case .medium: return t("Средняя")
            case .powerful: return t("Мощная")
            case .none: return t("Для разговора")
            }
        }
    }

    /// Вторая строка: чем этот разряд отличается от соседнего. Замеры —
    /// в `DEVELOPMENT.md`, «Какой моделью отвечать».
    var detail: String {
        switch role {
        case .embed:
            return t("Считает смысл заметок: поиск понимает суть, а не слова.")
        case .chat:
            switch tier {
            case .light:
                return t("Отвечает сразу, без раздумий, но иногда путает час встречи.")
            case .medium:
                return t("Справляется со всеми делами и отвечает голосом за секунды.")
            case .powerful:
                return t("Пишет по-русски чище всех. Нужен запас памяти.")
            case .none:
                return ""
            }
        }
    }

    /// «5,2 ГБ». Отдельно от `detail`: в строке вес стоит у края.
    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

/// Память и свободное место машины — одним значением.
///
/// Отдельный тип нужен ровно для того, чтобы `ModelCatalogue` остался
/// чистым: совет по ресурсам проверяется тестом на выдуманных числах,
/// а не на той технике, где случилось запустить прогон.
struct MachineResources: Equatable {
    let ram: Int64
    let freeDisk: Int64

    static func current() -> MachineResources {
        MachineResources(
            ram: Int64(ProcessInfo.processInfo.physicalMemory),
            freeDisk: Self.freeDisk()
        )
    }

    /// Свободное место там, где лежат модели, — в домашней папке.
    ///
    /// Не на системном томе: он доступен только для чтения и занят целиком.
    /// Слои Ollama кладёт в `~/.ollama/models`, и спрашивать надо про тот
    /// же том. Ключ «для важного» — тот же, которым считает своё место
    /// обновление (`UpdateService`) и мониторинг.
    private static func freeDisk() -> Int64 {
        let url = FileManager.default.homeDirectoryForCurrentUser
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0)
    }
}

/// Что предлагаем скачать и что советуем именно этой машине.
///
/// Состав выбран не по отзывам, а по единственной пробе, которая в проекте
/// есть: `DEVELOPMENT.md`, «Какой моделью отвечать». Там замерены вызовы
/// инструментов и **время устного ответа** — последнее и решает дело,
/// потому что вырез всё это время молча светится.
///
/// Поэтому в каталоге нет ни одной модели, которую здесь не запускали.
/// `qwen3:14b` просится третьим разрядом по имени семейства, но его никто
/// не замерял, а `gemma4:12b` в той же таблице показала, чем это кончается:
/// вызовы безупречны, устный ответ — до пятидесяти восьми секунд.
///
/// Все разговорные разряды обязаны уметь `tools`: без этого помощник
/// мёртв целиком. Это закреплено тестом на самой таблице.
enum ModelCatalogue {
    /// Запас на диске сверх веса самой модели: под векторную модель рядом
    /// и под то, чтобы машина не встала сразу после загрузки.
    static let diskReserve: Int64 = 3_000_000_000

    /// Порядок — порядок показа: от лёгкой к мощной, векторная последней.
    ///
    /// Веса сняты живьём: первые три — суммы слоёв из `/api/tags`,
    /// векторная — из манифеста реестра.
    static let offers: [ModelOffer] = [
        // Не `qwen3:4b`: та думает дольше всех в каталоге, и круг помощника
        // на ней шёл восемь секунд, а без раздумий она выносит рассуждение
        // прямо в ответ. У `qwen3:4b-instruct` раздумий нет вовсе — круг
        // за секунду, семь вызовов из семи. Промах один: «в пять» читает
        // то пятнадцатью, то восемнадцатью часами, и его ловит карточка.
        ModelOffer(
            tag: "qwen3:4b-instruct", role: .chat, tier: .light,
            bytes: 2_497_293_803, minRAM: 8_000_000_000
        ),
        // Без раздумий: семь вызовов из семи, шесть дат из шести и круг
        // за две секунды вместо тринадцати. Замеры — в `DEVELOPMENT.md`.
        ModelOffer(
            tag: RecommendedModel.chat, role: .chat, tier: .medium,
            bytes: 5_225_388_164, minRAM: 16_000_000_000,
            skipsThinking: true
        ),
        ModelOffer(
            tag: "gpt-oss:20b", role: .chat, tier: .powerful,
            bytes: 13_793_441_244, minRAM: 32_000_000_000
        ),
        ModelOffer(
            tag: RecommendedModel.embed, role: .embed, tier: .none,
            bytes: 274_302_030, minRAM: 8_000_000_000
        ),
    ]

    static var chat: [ModelOffer] {
        offers.filter { $0.role == .chat }
    }

    /// Самая лёгкая разговорная — по умолчанию ею отвечает голос.
    static var lightest: ModelOffer {
        chat.first { $0.tier == .light } ?? chat[0]
    }

    /// Просит ли каталог отвечать этой моделью без раздумий.
    ///
    /// Сравнение с меткой: `qwen3:8b` без раздумий, а `qwen3:4b` —
    /// другая модель, и признак на неё не распространяется.
    static func answersWithoutThinking(_ model: String) -> Bool {
        chat.contains { $0.skipsThinking && RecommendedModel.same(model, $0.tag) }
    }

    /// Векторная модель одна. Если её нет, каталог собран неверно —
    /// лучше пустое предложение, чем молчаливая подмена разговорной.
    static var embed: ModelOffer {
        offers.first { $0.role == .embed }
            ?? ModelOffer(
                tag: RecommendedModel.embed, role: .embed, tier: .none,
                bytes: 274_302_030, minRAM: 8_000_000_000
            )
    }

    /// По силам ли предложение машине.
    enum Fit: Equatable {
        case fits
        /// Сколько памяти не хватает. Названное число честнее отказа.
        case needsRAM(Int64)
        /// Сколько не хватает на диске.
        case needsDisk(Int64)
    }

    /// Чистая: ни диска, ни сети. Числа приходят аргументами, и тест
    /// подставляет свои.
    ///
    /// Памяти требуется вдвое против веса, округлённо до настоящей
    /// конфигурации (2,5 → 8, 5,2 → 16, 13,8 → 32). Вес — это сколько
    /// модель занимает на диске; в работе к нему добавляется контекст,
    /// и главное — она обязана уместиться **рядом с работой человека**.
    /// Это четвёртое требование из той же пробы, и нарушить его значит
    /// получить свист вентиляторов вместо ответа.
    ///
    /// Память проверяется раньше диска нарочно: место освобождают
    /// за минуту, а память не добавишь. Поэтому нехватка памяти гасит
    /// строку, а нехватка места — только называет цифру.
    static func fit(_ offer: ModelOffer, on machine: MachineResources) -> Fit {
        if machine.ram < offer.minRAM {
            return .needsRAM(offer.minRAM - machine.ram)
        }
        let needed = offer.bytes + diskReserve
        if machine.freeDisk < needed {
            return .needsDisk(needed - machine.freeDisk)
        }
        return .fits
    }

    /// Какую модель для разговора советуем этой машине.
    ///
    /// Самый тяжёлый разряд, прошедший оба порога. Не прошёл ни один —
    /// самый лёгкий: на экране должно стоять число недостачи, а не пустое
    /// место. Спорить о том, советовать ли непосильное, не нужно —
    /// `fit` рядом, и строка скажет правду.
    static func recommended(on machine: MachineResources) -> ModelOffer {
        let affordable = chat.filter { fit($0, on: machine) == .fits }
        guard let best = affordable.max(by: { $0.tier < $1.tier }) else {
            return chat.min(by: { $0.tier < $1.tier }) ?? embed
        }
        return best
    }

    /// Пара, которую ставит одна кнопка: разговорная и векторная.
    ///
    /// Разговорная первой — её ждут. Векторная весит 0,3 ГБ и потерпит.
    static func recommendedPair(on machine: MachineResources) -> [String] {
        [recommended(on: machine).tag, embed.tag]
    }
}

/// Готовая строка списка предложений: что написать и что показать справа.
///
/// Знакомство рисует белым по стеклу, настройки — строками формы
/// с системными цветами. Один вид на оба экрана был бы выдумкой, а вот
/// расходиться в том, **что именно строка говорит**, им нельзя: это ровно
/// тот случай, из которого вырос единый расчёт состояния выреза.
///
/// Поэтому все решения приняты здесь, а оба рисовальщика глупые.
struct ModelOfferRow: Equatable, Identifiable {
    /// Пометка у названия. Одна на строку, и порядок старшинства важен:
    /// человеку нужнее знать «эта выбрана», чем «эту советуем».
    enum Badge: Equatable {
        case none
        /// Советуем именно её этой машине.
        case recommended
        /// Скачана и выбрана — та, которой приложение отвечает.
        case selected
        /// Скачана, но отвечает другая.
        case installed
        /// Машине не по силам.
        case heavy
    }

    /// Что можно сделать со строкой.
    enum Action: Equatable {
        case none
        case install
        /// Скачана — можно сделать её основной.
        case select
        case installing(Double)
        /// Стоит в очереди за другой загрузкой.
        case queued
        /// Нажать нечего: не хватает памяти.
        case blocked
    }

    let offer: ModelOffer
    let badge: Badge
    let action: Action
    /// Чего не хватает, если не хватает. Нехватку места говорим, но
    /// кнопку оставляем: место освобождают за минуту.
    let warning: String?

    var id: String { offer.tag }
}

extension ModelCatalogue {
    /// Во что превращается каталог, когда известно состояние машины
    /// и загрузок. Чистая: ни сети, ни диска, ни настроек.
    ///
    /// - Parameters:
    ///   - installed: что уже скачано, из `ModelList`.
    ///   - selected: чем приложение отвечает сейчас.
    ///   - installing: что качается прямо сейчас, или `nil`.
    ///   - share: доля скачанного — нужна только качающейся строке.
    ///   - queued: что стоит в очереди.
    static func rows(
        on machine: MachineResources,
        installed: [ModelRef],
        selected: String,
        installing: String?,
        share: Double,
        queued: [String]
    ) -> [ModelOfferRow] {
        let advised = recommended(on: machine).tag
        return offers.map { offer in
            row(
                offer, on: machine, advised: advised, installed: installed,
                selected: selected, installing: installing, share: share, queued: queued
            )
        }
    }

    private static func row(
        _ offer: ModelOffer,
        on machine: MachineResources,
        advised: String,
        installed: [ModelRef],
        selected: String,
        installing: String?,
        share: Double,
        queued: [String]
    ) -> ModelOfferRow {
        // Сравнение с меткой: `nomic-embed-text` и `nomic-embed-text:latest` —
        // одна модель, а `qwen3:4b` и `qwen3:8b` — разные.
        let isInstalled = RecommendedModel.isInstalled(offer.tag, among: installed)
        let isSelected = RecommendedModel.same(selected, offer.tag)
        let isInstalling = installing.map { RecommendedModel.same($0, offer.tag) } ?? false
        let isQueued = queued.contains { RecommendedModel.same($0, offer.tag) }
        let verdict = fit(offer, on: machine)

        // Про память говорим, сколько её нужно, а не сколько не хватает:
        // «нужно 32 ГБ» человек сверит со своей машиной, а «не хватает 8»
        // заставит считать.
        // Строка перевода стоит вплотную к `tf(`: `check-strings.py` читает
        // только литерал сразу за скобкой, и перенос строки спрятал бы
        // от него непереведённое.
        //
        // У скачанной модели не говорим ничего. Поймано на снимке: строка
        // рабочей модели сообщала «нужно 32 ГБ памяти» машине с 24 — то
        // есть спорила с тем, что человек уже делает. Порог нужен, чтобы
        // советовать, а не чтобы возражать действительности.
        var warning: String?
        switch verdict {
        case .fits:
            warning = nil
        case _ where isInstalled:
            warning = nil
        case .needsRAM:
            let нужно = ByteCountFormatter.string(fromByteCount: offer.minRAM, countStyle: .file)
            warning = tf("Нужно %@ памяти", нужно)
        case let .needsDisk(short):
            let нехватка = ByteCountFormatter.string(fromByteCount: short, countStyle: .file)
            warning = tf("Не хватает %@ на диске", нехватка)
        }

        return ModelOfferRow(
            offer: offer,
            badge: badge(
                verdict: verdict, isSelected: isSelected, isInstalled: isInstalled,
                isAdvised: offer.tag == advised, role: offer.role
            ),
            action: action(
                verdict: verdict, isInstalling: isInstalling, isQueued: isQueued,
                isInstalled: isInstalled, isSelected: isSelected, share: share, role: offer.role
            ),
            warning: warning
        )
    }

    /// Старшинство пометок.
    ///
    /// Скачанная модель **никогда** не приглушается, даже если по нашей
    /// мерке машине не по силам. Поймано на живой машине: `gpt-oss:20b`
    /// у пользователя скачана и работает, а 24 ГБ памяти нашему порогу
    /// в 32 не отвечают — и строка с рабочей моделью гасла. Порог нужен,
    /// чтобы советовать, а не чтобы спорить с тем, что уже работает.
    ///
    /// Дальше: выбранная, скачанная, советуем, непосильная.
    private static func badge(
        verdict: Fit, isSelected: Bool, isInstalled: Bool,
        isAdvised: Bool, role: ModelOffer.Role
    ) -> ModelOfferRow.Badge {
        // У векторной модели выбора нет: она одна, и «выбрана» про неё
        // ничего не сообщает.
        if isSelected, role == .chat { return .selected }
        // «Рекомендуем» старше «скачана»: скачанность и так видна по кнопке
        // «Отвечать ею», а совет — единственное, что человеку здесь
        // подсказывают. На снимке это и вылезло: у машины, где всё скачано,
        // совет не показывался вовсе.
        if isAdvised, role == .chat { return .recommended }
        if isInstalled { return .installed }
        if case .needsRAM = verdict { return .heavy }
        return .none
    }

    private static func action(
        verdict: Fit, isInstalling: Bool, isQueued: Bool, isInstalled: Bool,
        isSelected: Bool, share: Double, role: ModelOffer.Role
    ) -> ModelOfferRow.Action {
        // Идущая загрузка старше всего: её видно, и отменить её — дело
        // той же строки.
        if isInstalling { return .installing(share) }
        if isQueued { return .queued }
        if isInstalled {
            // Выбранной делать нечего, а векторную выбирать негде:
            // её имя живёт отдельной настройкой в разделе «Заметки».
            if role == .embed || isSelected { return .none }
            // Скачанную даём выбрать и тогда, когда порог не сошёлся:
            // человек её уже скачал, и знает про свою машину больше нас.
            return .select
        }
        if case .needsRAM = verdict { return .blocked }
        return .install
    }
}
