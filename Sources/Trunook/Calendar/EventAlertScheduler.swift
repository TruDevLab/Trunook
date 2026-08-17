import TrunookXPC
import Foundation

/// Решает, когда показать предупреждение о ближайшем событии.
///
/// Работает опросом раз в пять секунд, а не таймерами на каждое событие:
/// событий за сутки бывает несколько десятков, они постоянно меняются
/// в хранилище, и переустанавливать под каждое свой таймер — источник
/// незакрытых утечек. Опрос дешевле и надёжнее.
final class EventAlertScheduler {
    var onAlert: ((CalendarItem, Int) -> Void)?

    private let settings: Settings
    private var timer: Timer?
    /// Уже показанные предупреждения: «идентификатор@порог».
    private var fired: Set<String> = []

    private var items: [CalendarItem] = []

    init(settings: Settings = .shared) {
        self.settings = settings
    }

    func start() {
        // Пять секунд, а не пятнадцать: шаг опроса — это и есть предельное
        // опоздание, а напоминание должно срабатывать в свой момент.
        // Проверка нескольких десятков записей стоит доли миллисекунды.
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.evaluate()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func update(items: [CalendarItem]) {
        self.items = items

        // Забываем отметки о событиях, которых больше нет: иначе набор рос бы
        // весь сеанс, а перенесённое событие не смогло бы напомнить о себе
        // заново.
        let alive = Set(items.map(\.id))
        fired = fired.filter { key in
            guard let id = key.split(separator: "@").first else { return false }
            return alive.contains(String(id))
        }
        evaluate()
    }

    private func evaluate() {
        guard settings.calendarEnabled else { return }
        let now = Date()

        for item in items {
            // События на весь день не имеют осмысленного момента начала.
            guard !item.isAllDay else { continue }
            let seconds = item.start.timeIntervalSince(now)

            for threshold in thresholds(for: item) {
                let key = "\(item.id)@\(threshold)"
                guard !fired.contains(key) else { continue }

                // Считаем в секундах, а не в минутах. С округлением до минуты
                // напоминание, назначенное на 19:35, срабатывало уже в 19:34:01:
                // до целой минуты оставалось «ноль». Для встречи за пять минут
                // это незаметно, а для напоминания «в момент наступления» —
                // промах почти на минуту.
                let target = TimeInterval(threshold) * 60
                // Порог проверяется окном, а не точкой: опрос дискретен,
                // и точное мгновение всегда проскочит.
                guard seconds <= target, seconds > target - Self.window else { continue }

                fired.insert(key)
                DebugLog.write("событие «\(item.title)»: предупреждение за \(threshold) мин")
                onAlert?(item, threshold)
            }
        }
    }

    /// Ширина окна срабатывания. Вдвое больше периода опроса, чтобы момент
    /// не мог провалиться между двумя проверками.
    private static let window: TimeInterval = 10

    /// За сколько минут предупреждать о конкретной записи.
    ///
    /// Напоминание отличается от встречи по смыслу: у встречи время начала —
    /// это когда надо уже быть на месте, поэтому нужен запас. У напоминания
    /// указанное время и есть момент, когда о нём просили напомнить, и
    /// срабатывать раньше срока неправильно.
    private func thresholds(for item: CalendarItem) -> [Int] {
        switch item.source {
        case .reminder, .things:
            return [0]
        case .event:
            var thresholds: [Int] = []
            if settings.eventLeadMinutes > 0 { thresholds.append(settings.eventLeadMinutes) }
            if settings.alertAtEventStart || settings.eventLeadMinutes == 0 { thresholds.append(0) }
            return thresholds
        }
    }
}
