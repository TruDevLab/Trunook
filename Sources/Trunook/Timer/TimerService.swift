import Foundation
import TrunookXPC

/// Таймер и секундомер.
///
/// Время **вычисляется из момента запуска**, а не накапливается тиком.
/// Тик неизбежно отстаёт, а после сна ноутбука отстаёт на всё время сна —
/// таймер на двадцать пять минут, поставленный перед закрытием крышки,
/// показывал бы двадцать четыре и после пробуждения.
///
/// Отсюда же вторая особенность: пока таймер идёт, служба ничего не шлёт
/// каждую секунду. Заведён один-единственный будильник ровно на момент
/// окончания, а цифры на экране перерисовывает сама панель, пока она открыта.
/// Закрытая панель не стоит приложению ни одного пробуждения процессора.
final class TimerService: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case timer
        case stopwatch

        var id: String { rawValue }

        var title: String {
            switch self {
            case .timer: return t("Таймер")
            case .stopwatch: return t("Секундомер")
            }
        }
    }

    /// Что идёт сейчас. Помидор — это чередование работы и перерыва,
    /// и различать их нужно хотя бы для того, чтобы не считать перерыв
    /// сделанным помидором.
    enum Phase: Equatable {
        case work
        case rest
    }

    /// Готовые длительности. Двадцать пять минут стоят в середине не случайно:
    /// это помидор, и попадать в него надо не глядя.
    static let presets: [Int] = [5, 10, 15, 25, 45]
    /// Длина помидора и перерыва после него.
    static let pomodoro: TimeInterval = 25 * 60
    static let restLength: TimeInterval = 5 * 60

    @Published private(set) var mode: Mode = .timer
    @Published private(set) var phase: Phase = .work
    /// Сколько помидоров доведено до конца. Сбрасывается перезапуском:
    /// это счёт за сегодняшний присест, а не статистика за год.
    @Published private(set) var harvest = 0
    /// Заданная длительность таймера.
    @Published private(set) var duration: TimeInterval = pomodoro

    /// Таймер дошёл до нуля. Плашку и виброотклик показывает контроллер:
    /// службе о вырезе знать незачем.
    var onFinished: ((Phase) -> Void)?

    /// Момент запуска. Ноль означает «стоит».
    ///
    /// Публикуется, хотя цифры перерисовывает не оно: по нему вырез узнаёт,
    /// что таймер пошёл, и раздвигается полоской. Без публикации чёлка
    /// оставалась бы свёрнутой до первой посторонней перерисовки.
    @Published private(set) var startedAt: Date?
    /// Сколько уже отсчитано до последней паузы.
    @Published private(set) var accumulated: TimeInterval = 0
    /// Единственный будильник — на момент окончания. Секундной дроби нет.
    private var alarm: Timer?

    private let settings: Settings

    init(settings: Settings = .shared) {
        self.settings = settings
    }

    // MARK: - Что показывать

    var isRunning: Bool { startedAt != nil }

    /// Сколько прошло с начала — с учётом пауз.
    var elapsed: TimeInterval {
        accumulated + (startedAt.map { Date().timeIntervalSince($0) } ?? 0)
    }

    /// Сколько осталось. Для секундомера смысла не имеет.
    var remaining: TimeInterval { max(0, duration - elapsed) }

    /// Ничего не начато: показывать нечего, сбрасывать нечего.
    var isClean: Bool { !isRunning && accumulated == 0 }

    /// Доля пройденного пути от нуля до единицы — по ней рисуется дуга.
    var progress: Double {
        guard mode == .timer, duration > 0 else { return 0 }
        return min(1, elapsed / duration)
    }

    // MARK: - Управление

    func select(mode: Mode) {
        guard mode != self.mode else { return }
        stopAlarm()
        startedAt = nil
        accumulated = 0
        self.mode = mode
        DebugLog.write("таймер: режим — \(mode.rawValue)")
    }

    func select(minutes: Int) {
        stopAlarm()
        startedAt = nil
        accumulated = 0
        phase = .work
        duration = TimeInterval(minutes * 60)
        DebugLog.write("таймер: заведён на \(minutes) мин")
    }

    func toggle() {
        isRunning ? pause() : start()
    }

    func start() {
        guard !isRunning else { return }
        // Таймер, доведённый до нуля, запускается заново, а не продолжает
        // уходить в минус.
        if mode == .timer, remaining <= 0 { accumulated = 0 }
        startedAt = Date()
        scheduleAlarm()
        DebugLog.write("таймер: пуск, режим \(mode.rawValue)")
    }

    func pause() {
        guard let startedAt else { return }
        accumulated += Date().timeIntervalSince(startedAt)
        self.startedAt = nil
        stopAlarm()
        DebugLog.write("таймер: пауза на \(Int(elapsed)) с")
    }

    func reset() {
        stopAlarm()
        startedAt = nil
        accumulated = 0
        phase = .work
        DebugLog.write("таймер: сброшен")
    }

    /// Добавить минуту на ходу — самая частая правка: «ещё чуть-чуть».
    func extend(byMinutes minutes: Int = 1) {
        guard mode == .timer else { return }
        duration += TimeInterval(minutes * 60)
        scheduleAlarm()
        DebugLog.write("таймер: продлён до \(Int(duration / 60)) мин")
    }

    func stop() {
        stopAlarm()
    }

    // MARK: - Будильник

    private func scheduleAlarm() {
        stopAlarm()
        guard mode == .timer, isRunning else { return }
        let left = remaining
        guard left > 0 else { return finish() }
        // Один будильник на всё ожидание. `RunLoop.common`, потому что при
        // открытом меню чужого приложения обычный режим цикла встаёт.
        let timer = Timer(timeInterval: left, repeats: false) { [weak self] _ in
            self?.finish()
        }
        RunLoop.main.add(timer, forMode: .common)
        alarm = timer
    }

    private func stopAlarm() {
        alarm?.invalidate()
        alarm = nil
    }

    private func finish() {
        stopAlarm()
        startedAt = nil
        accumulated = duration
        let finished = phase
        if phase == .work, duration >= Self.pomodoro { harvest += 1 }
        DebugLog.write("таймер: вышло время, фаза \(finished == .work ? "работа" : "перерыв")")
        onFinished?(finished)

        guard settings.pomodoroChainsRest else { return }
        // Помидор без перерыва — просто таймер. Перерыв заводится сам,
        // но не запускается: решать, отдыхать ли сейчас, всё-таки человеку.
        phase = finished == .work ? .rest : .work
        duration = phase == .rest ? Self.restLength : Self.pomodoro
        accumulated = 0
    }

    // MARK: - Запись времени

    /// Часы в виде «25:00», а при часе и больше — «1:05:00».
    static func clock(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
