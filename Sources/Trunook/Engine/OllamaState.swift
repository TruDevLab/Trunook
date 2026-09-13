import Foundation

/// Откуда на машине взялась Ollama.
///
/// Различать приходится потому, что лечение у них разное: приложение
/// запускается нажатием, а поставленное через Homebrew — командой, и
/// предлагать установку поверх рабочего Homebrew нельзя.
enum OllamaInstall: Equatable {
    /// Найден бандл приложения.
    case app(URL)
    /// Утилита есть, а бандла нет: поставлено пакетным менеджером.
    case brew(URL)
    /// Порт отвечает, а чем — неизвестно: docker, `ollama serve` руками,
    /// чужая машина на том же адресе.
    case foreign
}

/// Что с движком моделей прямо сейчас.
///
/// Одно состояние на всё приложение: и экран знакомства, и настройки
/// спрашивают его, а не считают заново каждый свой ответ. Два понятия
/// «жив ли движок» на двух экранах разошлись бы в первую же версию —
/// это ровно та беда, из которой вырос единый расчёт состояния выреза.
enum OllamaState: Equatable {
    case unknown
    case checking
    /// Адрес указан не местный: ставить нечего, движок чужой.
    case remote(String)
    /// Ни бандла, ни утилиты, ни ответа на порту.
    case absent
    /// Есть, но молчит.
    case stopped(OllamaInstall)
    case downloading(Double)
    /// Образ смонтирован, сверяется подпись.
    case verifying
    case copying
    /// Запустили и ждём, пока поднимется порт.
    case starting(waited: TimeInterval)
    case running(version: String?, from: OllamaInstall)
    case failed(OllamaFailure)

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    /// Идёт ли работа, которую нельзя начинать второй раз.
    var isBusy: Bool {
        switch self {
        case .checking, .downloading, .verifying, .copying, .starting: return true
        case .unknown, .remote, .absent, .stopped, .running, .failed: return false
        }
    }
}

/// Почему не получилось.
enum OllamaFailure: Equatable {
    case network
    case noSpace
    /// Образ скачался, но развернуть его не удалось.
    case damaged
    case unsigned
    /// Подписано, но не тем: так выглядит подмена — и так же однажды
    /// будет выглядеть смена сертификата у самой Ollama.
    case wrongIdentity
    /// В «Программы» не пишется. Пароля не просим никогда.
    case notWritable
    /// Запустили, а порт за отведённое время не ответил.
    case didNotStart

    var message: String {
        switch self {
        case .network:
            return t("Не удалось скачать Ollama. Проверьте сеть.")
        case .noSpace:
            return t("На диске не хватает места для Ollama.")
        case .damaged:
            return t("Образ Ollama не открылся. Попробуйте ещё раз.")
        case .unsigned:
            return t("У скачанного нет подписи. Установка отменена.")
        case .wrongIdentity:
            return t("Скачанное подписано не Ollama. Установка отменена.")
        case .notWritable:
            return t("В «Программы» не записать. Перетащите Ollama туда сами.")
        case .didNotStart:
            return t("Ollama не ответила. Откройте её и закончите установку.")
        }
    }
}

/// Строка состояния движка и кнопка рядом с ней.
///
/// Слова выбираются здесь, а не в вёрстке, и поэтому проверяются тестом
/// целиком: экранов два, а перечисление состояний одно, и пропустить
/// случай на одном из экранов — самый дешёвый способ показать человеку
/// пустую карточку.
struct OllamaStatusLine: Equatable {
    enum Action: Equatable {
        case none
        case install
        case start
        case check
        case cancel
        /// Показать смонтированный образ в Finder: дальше человек сам.
        case reveal
        /// Скопировать команду для Homebrew.
        case copyCommand
        /// Идёт работа — кнопки нет, но и бездействием это не назвать.
        case busy
    }

    let text: String
    let action: Action
}

/// Что написать о движке при каждом его состоянии.
enum OllamaStatusText {
    /// - Parameter weInstalled: Ollama поставлена нами. Тогда о ней можно
    ///   говорить как о своей работе — и обязательно сказать, что она
    ///   останется, даже если Trunook удалить.
    static func line(for state: OllamaState, weInstalled: Bool) -> OllamaStatusLine {
        switch state {
        case .unknown, .checking:
            return OllamaStatusLine(text: t("Проверяю движок…"), action: .busy)

        case let .remote(host):
            return OllamaStatusLine(text: tf("Модели берутся с %@", host), action: .none)

        case .absent:
            return OllamaStatusLine(
                text: t("Ollama не установлена. Скачаем и поставим её сами."),
                action: .install
            )

        case let .stopped(install):
            return stoppedLine(install)

        case let .downloading(share):
            let процент = Int((share * 100).rounded())
            return OllamaStatusLine(text: tf("Качаю Ollama — %d%%", процент), action: .cancel)

        case .verifying:
            return OllamaStatusLine(text: t("Проверяю подпись Ollama…"), action: .busy)

        case .copying:
            return OllamaStatusLine(text: t("Переношу Ollama в «Программы»…"), action: .busy)

        case let .starting(waited):
            // После десяти секунд дело, скорее всего, в её собственном окне:
            // при первом запуске Ollama просит права на свою утилиту.
            if waited >= 10 {
                return OllamaStatusLine(
                    text: t("Ollama открыла своё окно — закончите установку в нём."),
                    action: .busy
                )
            }
            return OllamaStatusLine(text: t("Запускаю Ollama…"), action: .busy)

        case let .running(version, _):
            return runningLine(version: version, weInstalled: weInstalled)

        case let .failed(reason):
            return OllamaStatusLine(text: reason.message, action: action(for: reason))
        }
    }

    private static func stoppedLine(_ install: OllamaInstall) -> OllamaStatusLine {
        switch install {
        case .app:
            return OllamaStatusLine(text: t("Ollama установлена, но не запущена."), action: .start)
        case .brew:
            // Ставить вторую копию поверх рабочего Homebrew — худшее,
            // что можно сделать, поэтому кнопки установки здесь нет.
            return OllamaStatusLine(
                text: t("Ollama стоит через Homebrew. Запустите «ollama serve»."),
                action: .copyCommand
            )
        case .foreign:
            return OllamaStatusLine(text: t("Движок не отвечает."), action: .check)
        }
    }

    private static func runningLine(version: String?, weInstalled: Bool) -> OllamaStatusLine {
        if weInstalled {
            return OllamaStatusLine(text: t("Ollama работает. Её поставил Trunook."), action: .check)
        }
        if let version, !version.isEmpty {
            return OllamaStatusLine(text: tf("Ollama %@ работает.", version), action: .check)
        }
        return OllamaStatusLine(text: t("Ollama работает."), action: .check)
    }

    /// Чем помочь после отказа. Отказ без выхода — тупик, и у каждого
    /// обязана быть своя кнопка.
    private static func action(for reason: OllamaFailure) -> OllamaStatusLine.Action {
        switch reason {
        case .notWritable:
            return .reveal
        case .didNotStart:
            return .start
        case .network, .noSpace, .damaged:
            return .install
        case .unsigned, .wrongIdentity:
            // Повторять нечего: то же скачается и так же не сойдётся.
            // Остаётся поставить руками.
            return .reveal
        }
    }
}
