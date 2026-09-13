import AppKit
import Foundation
import TrunookXPC

/// Движок моделей: жив ли он, и если нет — что с этим сделать.
///
/// Один на приложение по тому же доводу, что и у `ModelInstaller`: работа
/// идёт минутами, а окна знакомства и настроек за это время закрывают
/// и открывают снова, и второй такой объект показал бы пустую карточку
/// поверх идущей работы.
///
/// Скачивание образа живёт отдельно, в `OllamaDownload`; здесь только
/// опознание, запуск и ожидание порта.
final class OllamaEngine: ObservableObject {
    static let shared = OllamaEngine()

    @Published private(set) var state: OllamaState = .unknown

    private let settings: Settings
    private let client: ModelClient
    /// Отложенный опрос порта — чтобы отменить его, а не ждать вхолостую.
    private var waiting: DispatchWorkItem?
    /// Идущая установка. Живёт минутами, и терять её вместе с закрытым
    /// окном нельзя.
    private var downloading: OllamaDownload?

    init(settings: Settings = .shared, client: ModelClient = ModelClient()) {
        self.settings = settings
        self.client = client
    }

    /// Поставлена ли Ollama нами. Нужно словам на карточке: о своей работе
    /// говорить можно, о чужой установке — нельзя.
    var weInstalled: Bool { settings.didInstallOllamaApp }

    var line: OllamaStatusLine {
        OllamaStatusText.line(for: state, weInstalled: weInstalled)
    }

    // MARK: - Опознание

    /// Кто и где. Порядок важен: сначала адрес, потом порт, потом диск.
    ///
    /// Порт старше бандла — в этом вся суть. Ответивший порт значит, что
    /// движок работает, и дальше спрашивать нечего: так подхватывается
    /// и Homebrew, и docker, и `ollama serve`, запущенный руками.
    func refresh() {
        let address = settings.apiURL(for: .ollama)
        guard OllamaApp.isLocalAddress(address) else {
            settle(.remote(OllamaApp.host(of: address)))
            return
        }

        settle(.checking)
        client.ping(.ollama) { [weak self] up in
            guard let self else { return }
            guard up else {
                settle(OllamaApp.installed().map { .stopped($0) } ?? .absent)
                return
            }
            let from = OllamaApp.installed() ?? .foreign
            settle(.running(version: nil, from: from))
            // Версия нужна только строке и журналу: не прочиталась — пусть
            // состояние от этого не меняется.
            client.engineVersion(from: .ollama) { [weak self] version in
                guard let self, state.isRunning else { return }
                settle(.running(version: version, from: from))
            }
        }
    }

    // MARK: - Установка

    /// Скачивает Ollama и ставит её в «Программы».
    ///
    /// Держим загрузку полем: она живёт минутами, а владелец — один
    /// на приложение, и потерять её вместе с закрытым окном нельзя.
    func install() {
        guard !state.isBusy else { return }
        guard OllamaApp.isLocalAddress(settings.apiURL(for: .ollama)) else {
            DebugLog.write("движок: адрес чужой — ставить местную Ollama не нужно")
            return
        }

        let download = OllamaDownload(
            onState: { [weak self] next in self?.settle(next) },
            onInstalled: { [weak self] bundle in
                guard let self else { return }
                // Отмечаем до запуска: дальше о ней говорят как о нашей
                // работе, и сказать это надо, даже если порт не поднимется.
                settings.didInstallOllamaApp = true
                // Вперёд, а не в фон: у Ollama свой первый запуск со своим
                // окном, и спрятанное окно, в котором надо нажать, — тупик.
                launch(bundle, activates: true)
            }
        )
        downloading = download
        download.start()
    }

    /// Показать образ в Finder — после отказа переноса.
    func revealImage() {
        NSWorkspace.shared.activateFileViewerSelecting([OllamaDownload.imageFile])
    }

    func cancelInstall() {
        downloading?.cancel()
        downloading = nil
        refresh()
    }

    // MARK: - Запуск

    /// Открывает установленную Ollama и ждёт, пока поднимется порт.
    func start() {
        guard case let .stopped(install) = state else {
            // Запускать нечего — но спросить ещё раз не мешает: состояние
            // могло устареть, пока окно было закрыто.
            refresh()
            return
        }
        guard case let .app(bundle) = install else {
            // Homebrew мы не поднимаем: сервер, запущенный нами, умрёт
            // вместе с нами, и человек получит движок, работающий только
            // при открытом Trunook.
            DebugLog.write("движок: Ollama из Homebrew — запускать её не наше дело")
            return
        }
        launch(bundle, activates: false)
    }

    /// Открывает бандл и начинает ждать порт. Зовётся и после установки.
    func launch(_ bundle: URL, activates: Bool) {
        settle(.starting(waited: 0))
        OllamaApp.launch(bundle, activates: activates) { [weak self] opened in
            guard let self else { return }
            guard opened else {
                settle(.failed(.didNotStart))
                return
            }
            awaitPort(attempt: 0)
        }
    }

    /// Опрашивает порт по расписанию, пока не ответит или не выйдет время.
    private func awaitPort(attempt: Int) {
        guard let step = OllamaApp.waitStep(attempt: attempt) else {
            DebugLog.write("движок: порт не ответил за \(Int(OllamaApp.ceiling)) с")
            settle(.failed(.didNotStart))
            return
        }
        settle(.starting(waited: OllamaApp.waited(before: attempt)))

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            client.ping(.ollama) { [weak self] up in
                guard let self else { return }
                guard up else {
                    awaitPort(attempt: attempt + 1)
                    return
                }
                let прошло = OllamaApp.waited(before: attempt)
                DebugLog.write("движок: порт ответил через \(прошло) с")
                settle(.running(version: nil, from: OllamaApp.installed() ?? .foreign))
            }
        }
        waiting = work
        DispatchQueue.main.asyncAfter(deadline: .now() + step, execute: work)
    }

    /// Поднять движок, если он стоит и молчит.
    ///
    /// Зовётся при запуске приложения и перед открытием панели — то есть
    /// лечит самую частую беду: приложение стоит, не запущено, и первый
    /// вопрос дня падает.
    ///
    /// Без включённой модели не делает ничего: на чистой установке флаг
    /// выключен, и запускать чужое приложение без спроса нельзя.
    func ensureUp() {
        guard settings.ollamaEnabled, settings.ollamaAutoStart else { return }
        guard !state.isBusy, !state.isRunning else { return }

        switch state {
        case .unknown, .failed:
            refresh()
        case let .stopped(.app(bundle)):
            DebugLog.write("движок: Ollama стоит и молчит — поднимаю")
            launch(bundle, activates: false)
        default:
            break
        }
    }

    func cancelWait() {
        waiting?.cancel()
        waiting = nil
    }

    private func settle(_ next: OllamaState) {
        guard state != next else { return }
        state = next
    }
}
