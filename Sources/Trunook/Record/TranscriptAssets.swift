import TrunookXPC
import Foundation
import Speech

/// Языковые наборы расшифровки: что установлено и как поставить недостающее.
///
/// Отдельно от `ModelInstaller`, хотя оба показывают полосу скачивания:
/// тот качает модели Ollama по сети сам, а здесь качает система, к себе
/// и общим для всех приложений набором. Общего кода у них нет, общий только
/// вид карточки в настройках.
@MainActor
final class TranscriptAssets: ObservableObject {
    enum State: Equatable {
        /// Ещё не спрашивали.
        case unknown
        /// Система старая: расшифровки на ней нет вовсе.
        case unsupported
        /// Язык не знает ни один модуль расшифровки.
        case unsupportedLanguage
        case missing
        case downloading(Double)
        case installed
        case failed(String)
    }

    @Published private(set) var state: State = .unknown
    /// Языки, которые вообще можно расшифровать, — для списка в настройках.
    @Published private(set) var locales: [Locale] = []

    private var work: Task<Void, Never>?

    var isBusy: Bool {
        if case .downloading = state { return true }
        return false
    }

    // MARK: - Состояние

    func refresh(for locale: Locale) {
        guard #available(macOS 26, *) else {
            state = .unsupported
            return
        }
        // Скачивание не перебиваем опросом: оно идёт минутами, а настройки
        // за это время перерисовываются десятки раз.
        guard !isBusy else { return }

        work?.cancel()
        work = Task { [weak self] in
            let status = await Transcriber.status(for: locale)
            guard let self, !Task.isCancelled else { return }
            switch status {
            case .installed: state = .installed
            case .downloading: state = .downloading(0)
            case .supported: state = .missing
            case .unsupported: state = .unsupportedLanguage
            @unknown default: state = .unknown
            }
        }
    }

    /// Список языков — один раз за открытие настроек: он не меняется.
    func loadLocales() {
        guard #available(macOS 26, *), locales.isEmpty else { return }
        Task { [weak self] in
            let all = await Transcriber.supportedLocales()
            self?.locales = all
        }
    }

    // MARK: - Установка

    func install(for locale: Locale) {
        guard #available(macOS 26, *), !isBusy else { return }
        state = .downloading(0)
        work?.cancel()
        work = Task { [weak self] in
            do {
                try await Transcriber.install(for: locale) { share in
                    Task { @MainActor [weak self] in
                        guard let self, self.isBusy else { return }
                        self.state = .downloading(share)
                    }
                }
                self?.state = .installed
            } catch {
                DebugLog.write("расшифровка: набор не поставился — \(error.localizedDescription)")
                self?.state = .failed(t("Не удалось скачать"))
            }
        }
    }

    // MARK: - Имя языка

    /// Человеческое название языка на языке интерфейса.
    ///
    /// Не `locale.identifier`: `ru_RU` в списке настроек — это код,
    /// а не название, и выбирать по нему человек не должен.
    static func name(of locale: Locale) -> String {
        let display = Localization.shared.resolved.locale
        return display.localizedString(forIdentifier: locale.identifier)
            ?? locale.identifier
    }
}
