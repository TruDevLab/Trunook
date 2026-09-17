import Foundation
import TrunookXPC

/// Сколько воды помещается в один заход и как это называется словами.
///
/// Без обращений к вёрстке: границы ползунка, шаг и подписи — это правила,
/// а не рисунок. Ошибка здесь молчаливая: ползунок, у которого шаг не делит
/// границы нацело, не встаёт на свой максимум вовсе, и заметить это можно
/// только тем, что однажды не получилось записать литр.
enum WaterVolume {
    /// Глоток. Меньше записывать незачем: счёт за день от этого не меняется,
    /// а ползунок у самого края теряет точность.
    static let minimum = 50
    /// Бутылка. Больше за один заход не выпивают, а шкала, растянутая
    /// до двух литров, перестала бы попадать в стакан.
    static let maximum = 1000
    /// Шаг. Пятьдесят миллилитров — половина стакана на глаз: мельче человек
    /// всё равно не отличит, а крупнее не даст записать привычные 250.
    static let step = 50
    /// Что стоит на ползунке, когда записывают впервые, — стакан.
    static let standard = 250

    /// Подписанные деления. Остальные — короткие риски без цифр: подписать
    /// все двадцать значило бы заклеить шкалу числами, между которыми
    /// не видно самой шкалы.
    static let marks = [minimum, 250, 500, 750, maximum]

    static var range: ClosedRange<Int> { minimum...maximum }

    /// Все деления шкалы.
    static var ticks: [Int] {
        Array(stride(from: minimum, through: maximum, by: step))
    }

    /// Ближайшее деление, не выходя за границы.
    static func snap(_ milliliters: Int) -> Int {
        let bounded = min(max(milliliters, minimum), maximum)
        let steps = ((bounded - minimum) + step / 2) / step
        return min(maximum, minimum + steps * step)
    }

    /// Доля от начала шкалы, 0…1. В точки её переводит вёрстка: у панели
    /// и у плитки разная ширина.
    static func fraction(of milliliters: Int) -> Double {
        Double(min(max(milliliters, minimum), maximum) - minimum)
            / Double(maximum - minimum)
    }

    /// Обратно: какое деление под этой долей.
    static func volume(atFraction fraction: Double) -> Int {
        snap(minimum + Int((Double(maximum - minimum) * min(max(fraction, 0), 1)).rounded()))
    }

    /// «350 мл», «1,2 л».
    ///
    /// За день набегает больше литра, и «1200 мл» читается хуже, чем «1,2 л»:
    /// четыре цифры подряд глаз разбирает по одной. Порция всегда
    /// в миллилитрах — там больше литра не бывает.
    static func label(_ milliliters: Int) -> String {
        guard milliliters >= 1000 else { return tf("%d мл", milliliters) }
        let litres = (Double(milliliters) / 1000 * 10).rounded() / 10
        let formatter = NumberFormatter()
        formatter.locale = Localization.shared.resolved.locale
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        let text = formatter.string(from: NSNumber(value: litres)) ?? "\(litres)"
        return tf("%@ л", text)
    }
}

/// Во что столько наливают: рюмка, чашка, стакан, кружка, бутылка.
///
/// Числу в миллилитрах человек не верит на глаз: «350» — это много или мало,
/// сразу не скажешь, а «кружка» скажет. Посуда отвечает на это одним
/// значком, и ползунок перестаёт быть шкалой отвлечённых чисел.
///
/// Границы — привычные, а не ровные доли шкалы: 250 это стакан, 500 —
/// бутылка, и двигать их ради красивой арифметики значило бы врать про обе.
enum WaterVessel: CaseIterable {
    case shot
    case cup
    case glass
    case mug
    case bottle
    case bigBottle

    /// Верхняя граница посуды, включительно.
    var upperBound: Int {
        switch self {
        case .shot: return 50
        case .cup: return 150
        case .glass: return 250
        case .mug: return 400
        case .bottle: return 700
        case .bigBottle: return WaterVolume.maximum
        }
    }

    var title: String {
        switch self {
        case .shot: return t("рюмка")
        case .cup: return t("чашка")
        case .glass: return t("стакан")
        case .mug: return t("кружка")
        case .bottle: return t("бутылка")
        case .bigBottle: return t("большая бутылка")
        }
    }

    var symbol: String {
        switch self {
        case .shot: return "wineglass.fill"
        case .cup: return "cup.and.saucer.fill"
        // Стакан и кружка — один значок: кружки в наборе две, стакана
        // нет вовсе, и подменять его чем попало хуже, чем повторить
        // значок при разных словах. Отличает их подпись.
        case .glass, .mug: return "mug.fill"
        case .bottle, .bigBottle: return "waterbottle.fill"
        }
    }

    /// Какая посуда у этого объёма.
    ///
    /// Перебором по порядку, а не таблицей границ по месту: границы обязаны
    /// идти по возрастанию и покрывать шкалу целиком — объём, не попавший
    /// никуда, остался бы без значка молча.
    static func of(_ milliliters: Int) -> WaterVessel {
        allCases.first { milliliters <= $0.upperBound } ?? .bigBottle
    }
}

/// Что выпито за один день.
///
/// Заходами, а не одним числом: «1,2 л за пять подходов» и «1,2 л залпом» —
/// разные дни, и плитка показывает именно это. Для суммы заходы всё равно
/// пришлось бы хранить: отменить последний, не помня его, нечем.
struct WaterDay: Codable, Equatable {
    /// Полночь того дня, к которому относятся заходы.
    var day: Date
    /// Заходы в миллилитрах, в порядке записи.
    var portions: [Int]

    var total: Int { portions.reduce(0, +) }
    var count: Int { portions.count }

    static func empty(on date: Date, calendar: Calendar = .current) -> WaterDay {
        WaterDay(day: calendar.startOfDay(for: date), portions: [])
    }

    /// День сменился — счёт начинается с нуля.
    ///
    /// Проверяется при каждом чтении, а не таймером в полночь: машина
    /// полночь проспит, а таймер, который должен был сработать во сне,
    /// не срабатывает вовсе — счёт так и остался бы вчерашним.
    func rolled(to now: Date, calendar: Calendar = .current) -> WaterDay {
        calendar.isDate(day, inSameDayAs: now) ? self : .empty(on: now, calendar: calendar)
    }
}

/// Журнал воды: что записано за сегодня и что стоит на ползунке.
///
/// Отдельная служба, а не поле настроек: ползунок держат рукой, и значение
/// между кадрами перетаскивания надо где-то помнить — `@State` в этом
/// тулчейне недоступен.
final class WaterLog: ObservableObject {
    static let shared = WaterLog()

    /// Записанное за сегодня.
    @Published private(set) var day: WaterDay
    /// Что стоит на ползунке прямо сейчас.
    @Published private(set) var draft: Int

    private let settings: Settings
    private let calendar: Calendar

    init(settings: Settings = .shared, calendar: Calendar = .current, now: Date = Date()) {
        self.settings = settings
        self.calendar = calendar
        let stored = settings.waterDay.rolled(to: now, calendar: calendar)
        day = stored
        // Ползунок открывается на прошлом заходе: пьют из одной и той же
        // кружки, и выставлять её объём заново каждый раз — работа на пустом
        // месте.
        draft = stored.portions.last ?? WaterVolume.standard
    }

    /// Сверить день перед показом: между двумя открытиями панели могла
    /// пройти полночь.
    func refresh(now: Date = Date()) {
        let rolled = day.rolled(to: now, calendar: calendar)
        guard rolled != day else { return }
        day = rolled
        settings.waterDay = rolled
    }

    /// Подвинуть ползунок. Виброотклик — только на смене деления: держать
    /// его на каждом кадре значит трястись непрерывно.
    func setDraft(_ milliliters: Int) {
        let snapped = WaterVolume.snap(milliliters)
        guard snapped != draft else { return }
        draft = snapped
        Haptics.tap(.alignment)
    }

    /// Записать то, что стоит на ползунке. Возвращает записанное.
    @discardableResult
    func record(now: Date = Date()) -> Int {
        refresh(now: now)
        let portion = WaterVolume.snap(draft)
        var updated = day
        updated.portions.append(portion)
        day = updated
        settings.waterDay = updated
        DebugLog.write("вода: записано \(portion) мл, за день \(updated.total) мл")
        return portion
    }

    /// Отменить последний заход — нажали не то деление.
    ///
    /// Без подтверждения: отменяется ровно один заход, и повторить его стоит
    /// одного нажатия. Спрашивать «точно?» о том, что чинится тем же
    /// движением, — лишний разговор.
    func undoLast() {
        guard !day.portions.isEmpty else { return }
        var updated = day
        let removed = updated.portions.removeLast()
        day = updated
        settings.waterDay = updated
        DebugLog.write("вода: отменён заход \(removed) мл, за день \(updated.total) мл")
    }
}
