import Foundation

/// Какой моделью отвечать голосу.
///
/// Своя модель, а не общая с разговором: голосу скорость важнее всего.
/// Пока модель думает, вырез молча светится, и каждая лишняя секунда
/// читается как зависание, а не как работа. Письменный ответ человек
/// ждёт спокойнее — он видит, что текст идёт.
///
/// По умолчанию самая лёгкая модель каталога. Выбор хранится тем же видом,
/// что и модель команды (`ollama|qwen3:4b-instruct`); пустая строка —
/// «как в разговоре».
enum VoiceModel {
    /// Чем отвечать, или `nil` — моделью разговора.
    ///
    /// Выбранная, но не скачанная модель **не** подставляется. Иначе голос
    /// по умолчанию молчал бы у всех, кто поставил рекомендованную пару:
    /// лёгкой среди неё нет, и Ollama ответила бы «модели нет» на первый же
    /// вопрос. Человек услышал бы осечку там, где модель разговора стоит
    /// и работает.
    ///
    /// Сравнение с меткой: скачанная `qwen3:4b` не делает установленной
    /// `qwen3:4b-instruct` — это другая модель.
    static func resolve(stored: String, installed: [ModelRef], fallback: AIProvider) -> String? {
        let raw = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let wanted = ModelRef.parse(raw, fallback: fallback) else { return nil }
        let present = installed.contains {
            $0.provider == wanted.provider && RecommendedModel.same($0.name, wanted.name)
        }
        return present ? wanted.stored : nil
    }

    /// Значение по умолчанию: самая лёгкая разговорная модель каталога.
    static var defaultStored: String {
        ModelRef(provider: .ollama, name: ModelCatalogue.lightest.tag).stored
    }
}
