import Foundation
import Testing
@testable import Trunook

/// Очередь скачивания и общая доля по слоям.
///
/// Обе части проверяются на значениях: живая проверка стоила бы пяти
/// гигабайт загрузки на каждый прогон, а испортить здесь можно ровно
/// порядок и счёт.
@Suite("Очередь скачивания")
struct ModelQueueTests {
    private func ref(_ name: String) -> ModelRef {
        ModelRef(provider: .ollama, name: name)
    }

    // MARK: - Порядок

    @Test("Разговорная модель идёт перед векторной")
    func порядокПары() {
        var queue = ModelQueue()
        queue.push([RecommendedModel.chat, RecommendedModel.embed], installed: [])
        #expect(queue.next() == RecommendedModel.chat)
        #expect(queue.next() == RecommendedModel.embed)
        #expect(queue.next() == nil)
    }

    @Test("Одно имя дважды в очередь не встаёт")
    func дублиСливаются() {
        var queue = ModelQueue()
        queue.push(["qwen3:8b", "qwen3:8b"], installed: [])
        queue.push(["qwen3:8b"], installed: [])
        #expect(queue.waiting == ["qwen3:8b"])
    }

    /// Иначе нажавший «Установить рекомендованное» второй раз ждал бы
    /// повторной загрузки пяти гигабайт ни за чем.
    @Test("Уже скачанное в очередь не попадает")
    func скачанноеПропускается() {
        var queue = ModelQueue()
        queue.push(
            [RecommendedModel.chat, RecommendedModel.embed],
            installed: [ref("nomic-embed-text:latest")]
        )
        #expect(queue.waiting == [RecommendedModel.chat])
    }

    /// Разряды одного семейства — разные модели, и скачанная лёгкая
    /// не отменяет загрузку средней.
    @Test("Другой разряд того же семейства скачанным не считается")
    func разрядыРазные() {
        var queue = ModelQueue()
        queue.push(["qwen3:8b"], installed: [ref("qwen3:4b")])
        #expect(queue.waiting == ["qwen3:8b"])
    }

    @Test("Очередь опустошается целиком")
    func очередьОчищается() {
        var queue = ModelQueue()
        queue.push(["qwen3:8b", RecommendedModel.embed], installed: [])
        queue.clear()
        #expect(queue.waiting.isEmpty)
        #expect(queue.next() == nil)
    }

    // MARK: - Доля скачанного

    /// Ollama шлёт числа по каждому слою, и доля одного слоя на переходе
    /// к следующему падает с восьмидесяти процентов до нуля. Полоса
    /// не имеет права идти назад.
    @Test("Доля по двум слоям не убывает и кончается единицей")
    func доляНеУбывает() {
        let строки = [
            #"{"status":"pulling manifest"}"#,
            #"{"status":"pulling a1","digest":"sha256:a1","total":1000,"completed":500}"#,
            #"{"status":"pulling a1","digest":"sha256:a1","total":1000,"completed":1000}"#,
            // Объявился второй слой, в девять раз больше первого: доля
            // одного слоя тут и обрушивалась.
            #"{"status":"pulling b2","digest":"sha256:b2","total":9000,"completed":0}"#,
            #"{"status":"pulling b2","digest":"sha256:b2","total":9000,"completed":4500}"#,
            #"{"status":"pulling b2","digest":"sha256:b2","total":9000,"completed":9000}"#,
            #"{"status":"verifying sha256 digest"}"#,
            #"{"status":"success"}"#,
        ]

        var progress = ModelClient.PullProgress()
        var доли: [Double] = []
        for строка in строки {
            if let доля = progress.share(of: строка) { доли.append(доля) }
        }

        #expect(доли.count == 5)
        #expect(доли == доли.sorted())
        #expect(доли.last == 1)
    }

    @Test("Строка без чисел долю не двигает")
    func строкаБезЧиселНеСчитается() {
        var progress = ModelClient.PullProgress()
        #expect(progress.share(of: #"{"status":"pulling manifest"}"#) == nil)
        #expect(progress.share(of: "не json") == nil)
        #expect(progress.share(of: #"{"completed":10,"total":0}"#) == nil)
    }

    /// У строк без отпечатка слой один и тот же, а не новый каждый раз:
    /// иначе целое росло бы с каждой строкой, и доля топталась на месте.
    @Test("Строки без отпечатка считаются одним слоем")
    func безОтпечаткаОдинСлой() {
        var progress = ModelClient.PullProgress()
        #expect(progress.share(of: #"{"completed":250,"total":1000}"#) == 0.25)
        #expect(progress.share(of: #"{"completed":750,"total":1000}"#) == 0.75)
    }
}
