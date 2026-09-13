import Foundation
import TrunookXPC

/// Скачивание модели у Ollama — с полосой и без терминала.
///
/// До сих пор список моделей приложение только читало: нет модели — иди
/// в терминал и набери `ollama pull`. Для того, кто ставит Ollama впервые,
/// это тупик ровно в том месте, где всё уже почти работает.
///
/// Один на всё приложение: скачивание идёт минутами, а окно настроек
/// за это время закрывают и открывают снова, и второй объект показал бы
/// пустую полосу поверх идущей загрузки.
final class ModelInstaller: ObservableObject {
    static let shared = ModelInstaller()

    enum State: Equatable {
        case idle
        /// Доля скачанного, от нуля до единицы.
        case pulling(Double)
        case done
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    /// Что именно качается. Нужно вёрстке: кнопок «Скачать» на экране две,
    /// а полоса должна гореть только у своей.
    @Published private(set) var installing: String?
    /// Что ждёт своей очереди. Тоже вёрстке: у такой строки вместо кнопки
    /// стоит «в очереди», иначе человек нажмёт второй раз.
    @Published private(set) var waiting: [String] = []

    private let client: ModelClient
    private let models: ModelList
    private var task: Task<Void, Never>?
    private var queue = ModelQueue()
    /// Откуда качать оставшееся в очереди: у всей очереди провайдер один.
    private var queueProvider: AIProvider = .ollama

    init(client: ModelClient = ModelClient(), models: ModelList = .shared) {
        self.client = client
        self.models = models
    }

    var isBusy: Bool {
        if case .pulling = state { return true }
        return false
    }

    func isInstalling(_ name: String) -> Bool {
        // Сравнение с меткой, а не по семейству: иначе загрузка `qwen3:4b`
        // зажигала бы полосу и у строки `qwen3:8b`.
        isBusy && RecommendedModel.same(installing ?? "", name)
    }

    func install(_ name: String, from provider: AIProvider = .ollama) {
        guard !isBusy else { return }
        installing = name
        state = .pulling(0)
        DebugLog.write("модели: качаю \(name)")

        task = client.pull(
            name,
            from: provider,
            onProgress: { [weak self] share in
                self?.state = .pulling(share)
            },
            onFinish: { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    state = .done
                    // Список обязан узнать о новой модели сам: человек
                    // только что её скачал и ждёт увидеть в выборе, а не
                    // догадываться, что надо нажать «обновить».
                    models.refresh()
                    DebugLog.write("модели: \(name) скачана")
                case .failure(let error):
                    state = .failed(error.localizedDescription)
                    DebugLog.write("модели: \(name) не скачалась — \(error.localizedDescription)")
                    // Отказ опустошает очередь: одна честная ошибка лучше
                    // двух, а кнопки на строках рядом — повторить недолго.
                    if !queue.waiting.isEmpty {
                        queue.clear()
                        waiting = []
                        DebugLog.write("модели: очередь брошена после отказа")
                    }
                }
                installing = nil
                startNext()
            }
        )
    }

    /// Ставит подряд несколько моделей.
    ///
    /// Одна загрузка за раз остаётся — довод прежний, — но `install`
    /// молча выбрасывал запрос, пришедший во время работы. Кнопка
    /// «Установить рекомендованное» так поставила бы одну модель из двух
    /// и потеряла вторую без следа.
    func enqueue(_ names: [String], from provider: AIProvider = .ollama) {
        queueProvider = provider
        queue.push(names, installed: models.models(of: provider))
        waiting = queue.waiting
        guard !isBusy else { return }
        startNext()
    }

    /// Берёт следующую из очереди. Зовётся по окончании каждой загрузки —
    /// в том числе неудачной, где очередь уже опустошена.
    private func startNext() {
        guard !isBusy, let next = queue.next() else {
            waiting = queue.waiting
            return
        }
        waiting = queue.waiting
        install(next, from: queueProvider)
    }

    func cancel() {
        task?.cancel()
        task = nil
        installing = nil
        queue.clear()
        waiting = []
        state = .idle
    }

    /// Убирает след прошлой попытки, чтобы отказ не висел на экране вечно.
    func forget() {
        guard !isBusy else { return }
        state = .idle
    }
}

/// Очередь имён на скачивание.
///
/// Отдельным значением, без сети и без состояния загрузки: порядок —
/// единственное, что здесь можно испортить, и проверять его надо тестом,
/// а не живой загрузкой на пять гигабайт.
struct ModelQueue: Equatable {
    private(set) var waiting: [String] = []

    /// Добавляет в хвост то, чего там ещё нет и что ещё не скачано.
    ///
    /// Уже установленное не ставится в очередь вовсе: нажав
    /// «Установить рекомендованное» второй раз, человек ждал бы повторной
    /// загрузки пяти гигабайт ни за чем.
    mutating func push(_ names: [String], installed: [ModelRef]) {
        for name in names {
            guard !RecommendedModel.isInstalled(name, among: installed) else { continue }
            guard !waiting.contains(where: { RecommendedModel.same($0, name) }) else { continue }
            waiting.append(name)
        }
    }

    mutating func next() -> String? {
        guard !waiting.isEmpty else { return nil }
        return waiting.removeFirst()
    }

    mutating func clear() {
        waiting = []
    }
}
