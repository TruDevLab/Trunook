import TrunookXPC
import AppKit
import Foundation

/// Кратковременное событие, которое временно расширяет свёрнутый вырез.
///
/// Содержимое раскладывается по бокам от аппаратной чёлки: слева значок,
/// справа значение. Середину закрывает сам вырез.
struct Activity: Identifiable, Equatable {
    let id = UUID()
    let kind: Kind
    /// Точка отсчёта для анимаций внутри плашки — например, бегущей строки.
    let createdAt = Date()

    enum Kind: Equatable {
        case meeting(item: CalendarItem, minutesBefore: Int)
        /// Ход и итог быстрой команды.
        case command(text: String, state: CommandState)
        /// Что-то скопировали. По этой плашке открывается история буфера.
        case clipboard(text: String, kind: ClipboardEntry.Kind)
        /// На полке лежат файлы. Держится, пока полка не опустеет.
        case shelf(count: Int)
        /// Вышло время таймера. Текст готовит контроллер: плашке незачем
        /// знать про помидоры.
        case timer(text: String)
        /// Погода: текст и значок готовит служба, плашка их только рисует.
        case weather(text: String, symbol: String)
        /// Экран перестали или снова стали гасить.
        case caffeine(change: CaffeineChange)
        /// Данных не несёт намеренно: сведения о треке доезжают порциями,
        /// и снимок, сделанный в момент переключения, застывал бы с прежним
        /// исполнителем и без обложки. Плашка читает их живьём.
        case trackChanged
        case powerConnected(percentage: Int)
        case powerDisconnected(percentage: Int)
        case lowBattery(percentage: Int)
    }

    /// Чем важнее событие, тем выше приоритет. Событие с приоритетом ниже
    /// текущего не показывается вовсе: показать его с опозданием хуже,
    /// чем не показать — предупреждение о разряде, всплывшее через минуту
    /// после смены трека, только сбивает с толку.
    var priority: Int {
        switch kind {
        // Отклик на нажатие клавиши важнее всего: пользователь ждёт его
        // прямо сейчас и связывает со своим действием.
        case .command: return 5
        // Вровень со встречей: вышедшее время — то, ради чего таймер
        // и заводили, и пропустить его значит обессмыслить всю затею.
        case .timer: return 4
        // Встреча следом: её пропуск нельзя отменить, в отличие
        // от незамеченной смены трека или уровня заряда.
        case .meeting: return 4
        // Отклик на ⌘C: человек только что нажал клавиши и связывает
        // плашку со своим действием — но пропущенная встреча дороже.
        case .clipboard: return 3
        // Вровень с копированием: плашка полки тоже отклик на действие руками.
        case .shelf: return 3
        case .lowBattery: return 3
        // Вровень с копированием: это отклик на нажатие, и человек связывает
        // плашку со своим действием.
        case .caffeine: return 3
        // Ниже разряда: дождь через два часа подождёт, а батарея — нет.
        case .weather: return 2
        case .powerConnected, .powerDisconnected: return 2
        case .trackChanged: return 1
        }
    }

    var duration: TimeInterval {
        switch kind {
        case let .command(_, state):
            switch state {
            // Пока команда идёт, плашка висит: локальная модель на холодную
            // думает почти минуту, и молчаливое ожидание выглядит как отказ.
            // Снимет её итоговая плашка — у неё тот же приоритет.
            case .running: return 300
            // Ошибку читают, успех только замечают.
            case .failed: return 5
            case .done: return 3
            }
        // Дольше прочих: нужно время прочитать название и нажать «подключиться».
        case .meeting: return 9
        // Столько же: об окончании надо успеть узнать, даже отвернувшись.
        case .timer: return 9
        // Дольше прочих мелких: по плашке нужно успеть попасть курсором,
        // чтобы открыть историю.
        case .clipboard: return 4
        // Без срока: висит, пока на полке что-то есть.
        case .shelf: return .infinity
        case .lowBattery: return 4
        case .weather: return 4
        // Столько же, сколько смене трека, и по той же причине: нажимают
        // по чашке в раскрытой панели, а плашку видно только после того,
        // как курсор ушёл, — ей нужно время пережить этот уход.
        case .caffeine: return 4
        case .powerConnected, .powerDisconnected: return 2.5
        // Дольше остальных: длинному названию нужно время проехать.
        case .trackChanged: return 4
        }
    }


    /// По плашке можно нажать. Такие не убираются при наведении курсора:
    /// иначе до них было бы физически не дотянуться.
    var isInteractive: Bool {
        switch kind {
        case .clipboard, .shelf: return true
        default: return false
        }
    }

    static func == (lhs: Activity, rhs: Activity) -> Bool {
        lhs.id == rhs.id
    }
}

/// Что случилось с удержанием экрана.
///
/// Отдельным типом, а не флагом «включено», потому что случаев три, а не два:
/// истёкший срок — это не то же самое, что выключение рукой. Человек его
/// не нажимал, и не сказать ему об этом значит оставить его гадать, почему
/// экран вдруг снова гаснет.
enum CaffeineChange: Equatable {
    /// Включили. Минуты — заданный срок; ноль означает «без ограничения».
    case on(minutes: Int)
    case off
    case expired
}

enum CommandState: Equatable {
    case running
    case done
    case failed
}

extension Activity.Kind {
    /// Короткое имя для журнала отладки.
    var label: String {
        switch self {
        case .command: return "команда"
        case .clipboard: return "копирование"
        case .shelf: return "полка"
        case .timer: return "таймер"
        case .weather: return "погода"
        case .caffeine: return "бодрость"
        case .meeting: return "встреча"
        case .trackChanged: return "смена трека"
        case .powerConnected: return "зарядка подключена"
        case .powerDisconnected: return "зарядка отключена"
        case .lowBattery: return "низкий заряд"
        }
    }
}

/// Решает, какое событие показывать прямо сейчас.
final class ActivityCenter: ObservableObject {
    @Published private(set) var current: Activity?

    private var dismissTimer: Timer?
    private let settings: Settings

    /// Что играет прямо сейчас — для объявления о смене трека.
    ///
    /// Замыканием, а не полем: плашка смены трека намеренно не несёт данных
    /// (сведения доезжают порциями и снимок застывал бы с прежним
    /// исполнителем), и текст для неё читается живьём в момент показа.
    var nowPlaying: (() -> NowPlaying?)?

    init(settings: Settings = .shared) {
        self.settings = settings
    }

    /// Сказать вслух то, что показано.
    ///
    /// Плашка — сообщение о состоянии: она не забирает фокус и ничего
    /// не спрашивает. Для того, кто её не видит, она до сих пор не значила
    /// ровно ничего: вышло время таймера, разрядилась батарея, началась
    /// встреча, команда упала с ошибкой — всё это появлялось на экране молча.
    ///
    /// Одна точка на все четырнадцать видов событий: сюда они и так все
    /// приходят, и объявлять их по месту значило бы четырнадцать раз забыть.
    private func announce(_ activity: Activity) {
        let text = ActivityView.text(for: activity.kind, track: nowPlaying?())
        guard !text.isEmpty else { return }
        // Важное перебивает начатую фразу, остальное дожидается своей очереди:
        // разряженную батарею нельзя ставить в хвост за сменой трека.
        let level: NSAccessibilityPriorityLevel = activity.priority >= 4 ? .high : .medium
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: text,
                .priority: level.rawValue,
            ]
        )
    }

    /// Сколько плашка висит на самом деле: свой срок, растянутый настройкой.
    ///
    /// Отдельно от `Activity.duration` потому, что тот отвечает на вопрос
    /// «сколько этому событию нужно по существу» — девять секунд встрече,
    /// две смене питания, — а настройка на все эти сроки смотрит одинаково.
    /// Смешать их значило бы прописать множитель в четырнадцати местах.
    func hold(for activity: Activity) -> TimeInterval {
        let base = activity.duration
        guard base.isFinite else { return base }
        let scale = settings.activityHold
        guard scale != 1 else { return base }
        // Ноль — «пока не уберу»: убирает такую плашку наведение на вырез.
        guard scale > 0 else { return .infinity }
        return base * TimeInterval(scale)
    }

    func present(_ kind: Activity.Kind) {
        let activity = Activity(kind: kind)
        if let current, current.priority > activity.priority {
            DebugLog.write("событие \(kind.label) отброшено: показывается более важное")
            return
        }
        show(activity)
    }

    func dismiss() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        guard let current else { return }
        DebugLog.write("событие \(current.kind.label) убрано досрочно")
        self.current = nil
    }

    private func show(_ activity: Activity) {
        dismissTimer?.invalidate()
        dismissTimer = nil
        current = activity
        announce(activity)

        // Плашка полки висит без срока: она сообщает не о событии, а о том,
        // что файлы отложены и о них не забыли. Убирает её крестик или
        // опустевшая полка.
        let hold = hold(for: activity)
        guard hold.isFinite else {
            DebugLog.write("событие \(activity.kind.label) показано без срока")
            return
        }
        DebugLog.write("событие \(activity.kind.label) показано на \(hold) с")

        let timer = Timer(timeInterval: hold, repeats: false) { [weak self] _ in
            guard let self, self.current == activity else { return }
            DebugLog.write("событие \(activity.kind.label) истекло")
            self.current = nil
        }
        // .common, иначе таймер замирает, пока пользователь тянет ползунок
        // или держит открытым меню.
        RunLoop.main.add(timer, forMode: .common)
        dismissTimer = timer
    }
}
