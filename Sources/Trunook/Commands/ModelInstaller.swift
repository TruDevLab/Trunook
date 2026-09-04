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

    private let client: ModelClient
    private let models: ModelList
    private var task: Task<Void, Never>?

    init(client: ModelClient = ModelClient(), models: ModelList = .shared) {
        self.client = client
        self.models = models
    }

    var isBusy: Bool {
        if case .pulling = state { return true }
        return false
    }

    func isInstalling(_ name: String) -> Bool {
        isBusy && RecommendedModel.base(of: installing ?? "") == RecommendedModel.base(of: name)
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
                }
                installing = nil
            }
        )
    }

    func cancel() {
        task?.cancel()
        task = nil
        installing = nil
        state = .idle
    }

    /// Убирает след прошлой попытки, чтобы отказ не висел на экране вечно.
    func forget() {
        guard !isBusy else { return }
        state = .idle
    }
}
