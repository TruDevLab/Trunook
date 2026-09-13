import Foundation
import Testing
@testable import Trunook

/// Какой моделью отвечает голос.
@Suite("Модель голоса")
struct VoiceModelTests {
    private func скачано(_ names: String...) -> [ModelRef] {
        names.map { ModelRef(provider: .ollama, name: $0) }
    }

    /// Голосу важнее скорость: пока модель думает, вырез молча светится.
    @Test("По умолчанию голос отвечает самой лёгкой моделью каталога")
    func поУмолчаниюЛёгкая() {
        let имя = "trunook.tests." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: имя) else {
            Issue.record("не завёлся набор настроек")
            return
        }
        defer { defaults.removePersistentDomain(forName: имя) }

        let settings = Settings(defaults: defaults)
        #expect(settings.voiceModel == "ollama|" + ModelCatalogue.lightest.tag)
    }

    @Test("Скачанная модель голоса подставляется")
    func скачаннаяПодставляется() {
        let выбор = VoiceModel.resolve(
            stored: "ollama|qwen3:4b-instruct",
            installed: скачано("qwen3:8b", "qwen3:4b-instruct"),
            fallback: .ollama
        )
        #expect(выбор == "ollama|qwen3:4b-instruct")
    }

    /// Иначе голос по умолчанию молчал бы у всех, кто поставил
    /// рекомендованную пару: лёгкой среди неё нет.
    @Test("Не скачанная модель не подставляется — отвечает модель разговора")
    func нескачаннаяНеПодставляется() {
        let выбор = VoiceModel.resolve(
            stored: "ollama|qwen3:4b-instruct",
            installed: скачано("qwen3:8b", "nomic-embed-text:latest"),
            fallback: .ollama
        )
        #expect(выбор == nil)
    }

    /// Скачанная `qwen3:4b` — другая модель, чем `qwen3:4b-instruct`,
    /// хотя семейство одно.
    @Test("Модель того же семейства за выбранную не считается")
    func семействоНеСчитается() {
        let выбор = VoiceModel.resolve(
            stored: "ollama|qwen3:4b-instruct",
            installed: скачано("qwen3:4b"),
            fallback: .ollama
        )
        #expect(выбор == nil)
    }

    @Test("«Как в разговоре» — своей модели у голоса нет")
    func какВРазговоре() {
        #expect(VoiceModel.resolve(stored: "", installed: скачано("qwen3:8b"), fallback: .ollama) == nil)
        #expect(VoiceModel.resolve(stored: "  ", installed: скачано("qwen3:8b"), fallback: .ollama) == nil)
    }

    /// Та же модель у другого провайдера — это другой сервер, и за скачанную
    /// у Ollama её выдавать нельзя.
    @Test("Модель чужого провайдера за скачанную у Ollama не считается")
    func чужойПровайдер() {
        let выбор = VoiceModel.resolve(
            stored: "ollama|qwen3:4b-instruct",
            installed: [ModelRef(provider: .lmStudio, name: "qwen3:4b-instruct")],
            fallback: .ollama
        )
        #expect(выбор == nil)
    }

    @Test("Метка latest не мешает сравнению")
    func меткаLatest() {
        let выбор = VoiceModel.resolve(
            stored: "ollama|llama3.2",
            installed: скачано("llama3.2:latest"),
            fallback: .ollama
        )
        #expect(выбор == "ollama|llama3.2")
    }
}
