/// Кто отвечает на запросы к модели.
///
/// Ollama была единственным ответчиком, и её имя разошлось по всему коду
/// и по настройкам. Но разговаривать есть с чем ещё: почти всё, что отвечает
/// на вопросы — и местное (LM Studio, llama.cpp, vLLM, Unsloth Studio),
/// и облачное, — говорит на одном и том же языке, совместимом с OpenAI.
/// Требовать от человека держать Ollama ради одного Trunook не за что.
///
/// Список — это **преднастройки, а не поддержка**. Приложение не умеет
/// ничего особенного ни про один из этих сервисов: оно знает их адреса,
/// только чтобы человеку не пришлось искать адрес самому и не ошибиться
/// в нём молча. Любой не перечисленный подключается «Кастомным провайдером»
/// с тем же успехом.
enum AIProvider: String, CaseIterable, Identifiable {
    // Своё, на этой же машине.
    case ollama
    case lmStudio
    case llamaCpp
    case vllm
    case unsloth
    // Облачное.
    case openAI
    case anthropic
    case gemini
    case openRouter
    case groq
    case deepSeek
    // Всё остальное.
    case custom

    var id: String { rawValue }

    /// На каком языке разговаривать.
    ///
    /// Диалекта два, а провайдеров дюжина: у Ollama свой формат запроса
    /// и потока, у всех прочих — общий. Клиент спрашивает **диалект**,
    /// а не провайдера: иначе `switch` по дюжине случаев завёлся бы
    /// в каждом месте, где различаются два.
    enum Dialect {
        case ollama
        case openAI
    }

    var dialect: Dialect { self == .ollama ? .ollama : .openAI }

    /// Работает ли на этой же машине. От этого зависит только порядок
    /// в списке: своё выше облачного — оно и есть обычный случай.
    var isLocal: Bool {
        switch self {
        case .ollama, .lmStudio, .llamaCpp, .vllm, .unsloth: return true
        default: return false
        }
    }

    static var local: [AIProvider] { allCases.filter(\.isLocal) }
    static var cloud: [AIProvider] { allCases.filter { !$0.isLocal && $0 != .custom } }

    var title: String {
        switch self {
        case .ollama: return "Ollama"
        case .lmStudio: return "LM Studio"
        case .llamaCpp: return "llama.cpp"
        case .vllm: return "vLLM"
        case .unsloth: return "Unsloth Studio"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        case .openRouter: return "OpenRouter"
        case .groq: return "Groq"
        case .deepSeek: return "DeepSeek"
        case .custom: return t("Кастомный провайдер")
        }
    }

    /// Адрес, который подставится при выборе. У кастомного его нет —
    /// поле остаётся пустым, и человек вписывает свой.
    var presetURL: String? {
        switch self {
        case .ollama: return nil
        case .lmStudio: return "http://127.0.0.1:1234/v1"
        case .llamaCpp: return "http://127.0.0.1:8080/v1"
        case .vllm: return "http://127.0.0.1:8000/v1"
        case .unsloth: return "http://127.0.0.1:8888/v1"
        case .openAI: return "https://api.openai.com/v1"
        // У Anthropic и Google свой формат ответа, но оба держат вход,
        // совместимый с OpenAI, — эти адреса ведут именно к нему.
        case .anthropic: return "https://api.anthropic.com/v1"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .deepSeek: return "https://api.deepseek.com/v1"
        case .custom: return nil
        }
    }

    /// Спрашивают ли ключ. У Ollama его нет вовсе.
    ///
    /// У местных серверов ключа обычно тоже нет — но «обычно» здесь не годится:
    /// LM Studio и vLLM запускают и с ключом, и поле, спрятанное по догадке
    /// о чужой настройке, оставило бы человека без единственного места, где
    /// его вписать.
    var usesKey: Bool { self != .ollama }

    /// Уходит ли запрос в интернет. Об этом сказано прямо в настройках:
    /// приложение построено на том, что наружу не уходит ничего, и выбор,
    /// который это меняет, обязан назвать себя сам.
    var isRemote: Bool { !isLocal && self != .custom }
}

/// Модель вместе с тем, кто её отдаёт.
///
/// Одного имени стало мало, когда провайдеров разрешили держать несколько:
/// «gpt-oss-20b» бывает и у местного сервера, и у облачного, а `gemma3:4b` —
/// и у Ollama, и у любого, кто её положил. По имени, оторванному от хозяина,
/// запрос ушёл бы не туда — и молча, потому что ответил бы кто-то из двух.
struct ModelRef: Equatable, Hashable {
    let provider: AIProvider
    let name: String

    /// Как это лежит в настройках и в команде.
    ///
    /// Разделитель — вертикальная черта: косая в именах моделей встречается
    /// сплошь и рядом (`unsloth/gemma-4-…`, `hf.co/Qwen/…`), а эта — нет.
    var stored: String { provider.rawValue + Self.separator + name }

    private static let separator = "|"

    /// Разбор сохранённого.
    ///
    /// Имя без разделителя — из тех времён, когда провайдер был один.
    /// Такие имена дочитываются как принадлежащие основному провайдеру
    /// и переписываются набело при первой загрузке команд.
    static func parse(_ raw: String, fallback: AIProvider) -> ModelRef? {
        guard !raw.isEmpty else { return nil }
        guard let mark = raw.range(of: separator) else {
            return ModelRef(provider: fallback, name: raw)
        }
        let head = String(raw[raw.startIndex..<mark.lowerBound])
        let tail = String(raw[mark.upperBound...])
        guard let provider = AIProvider(rawValue: head), !tail.isEmpty else {
            return ModelRef(provider: fallback, name: raw)
        }
        return ModelRef(provider: provider, name: tail)
    }

    /// Имя для показа: без приставки `library/`, которая есть почти у всех
    /// моделей Ollama и потому не различает ничего.
    var shortName: String {
        guard let slash = name.lastIndex(of: "/") else { return name }
        return String(name[name.index(after: slash)...])
    }
}

/// Модели, которые приложение предлагает скачать, когда своих ещё нет.
///
/// Две, и они разного рода. Первая отвечает словами, вторая не отвечает
/// вовсе — она считает векторы смысла, и просить её о чём-то текстом
/// бессмысленно. Человеку это неочевидно, поэтому в настройках они стоят
/// раздельно и подписаны по делу.
enum RecommendedModel {
    /// Отвечает на вопросы. Совпадает со значением `ollamaModel`
    /// по умолчанию — иначе «рекомендованная» и «стоит по умолчанию»
    /// оказались бы разными моделями.
    static let chat = "gemma4:12b"

    /// Считает векторы. Маленькая и быстрая: вектор нужен на каждую заметку,
    /// и модель на несколько гигабайт считала бы их полдня.
    static let embed = "nomic-embed-text"

    /// Есть ли такая модель среди уже установленных.
    ///
    /// Сравнение по имени без метки версии: Ollama зовёт скачанное
    /// `nomic-embed-text:latest`, а просят её обычно без метки, и точное
    /// сравнение отвечало бы «нет» на установленную модель.
    static func isInstalled(_ name: String, among models: [ModelRef]) -> Bool {
        let wanted = base(of: name)
        return models.contains { base(of: $0.name) == wanted }
    }

    static func base(of name: String) -> String {
        let text = name.hasPrefix("ollama|") ? String(name.dropFirst(7)) : name
        guard let colon = text.firstIndex(of: ":") else { return text }
        return String(text[text.startIndex..<colon])
    }
}
