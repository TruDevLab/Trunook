import AppKit

/// На каких экранах живёт остров.
enum NotchScreenMode: String, CaseIterable, Identifiable {
    /// Только главный экран — как было всегда.
    case notched
    /// Там, где курсор: окно переезжает на экран вслед за рукой.
    case cursor
    /// На всех экранах: полный остров на главном, на остальных — полоска,
    /// которую можно раскрыть наведением.
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notched: return t("С вырезом")
        case .cursor: return t("Где курсор")
        case .all: return t("Все экраны")
        }
    }

    /// Пояснение под выбором — своё у каждого режима.
    var hint: String {
        switch self {
        case .notched: return t("Остров живёт только на главном экране.")
        case .cursor: return t("Остров переезжает на экран под курсором.")
        case .all: return t("События — на главном экране, на остальных тонкая полоска.")
        }
    }
}

/// Экран, снятый в простые значения: выбор проверяется тестом без мониторов.
struct ScreenSlot: Equatable {
    let id: CGDirectDisplayID
    let frame: CGRect
    let hasNotch: Bool
    /// Зона раскрытия по наведению — у настоящей чёлки или условной.
    let trigger: CGRect
}

/// Какой экран достаётся основному окну и какие — отражениям.
enum NotchScreenChoice {
    /// Главный экран: с системной чёлкой, а нет такого — основной монитор
    /// из системных настроек. Основной `NSScreen.screens` отдаёт первым.
    static func home(_ screens: [ScreenSlot]) -> CGDirectDisplayID? {
        (screens.first { $0.hasNotch } ?? screens.first)?.id
    }

    /// Экран основного окна.
    ///
    /// `isBusy` — с островом работают руками: наведён, открыта панель,
    /// кольцо, идёт голос. Тогда окно остаётся где было, иначе панель уехала
    /// бы из-под руки, стоило курсору задеть соседний экран.
    static func host(
        mode: NotchScreenMode,
        screens: [ScreenSlot],
        cursor: CGPoint,
        current: CGDirectDisplayID?,
        isBusy: Bool
    ) -> CGDirectDisplayID? {
        guard let home = home(screens) else { return nil }
        let alive = current.flatMap { id in screens.first { $0.id == id }?.id }
        switch mode {
        case .notched:
            return home
        case .cursor:
            if isBusy, let alive { return alive }
            return screens.first { contains($0.frame, cursor) }?.id ?? alive ?? home
        case .all:
            // Дома остров со всеми полосками и плашками. На другой экран
            // он выезжает, только когда руку подвели к полоске, и возвращается,
            // как только с ним закончили.
            if isBusy, let alive { return alive }
            return screens.first { $0.id != home && $0.trigger.contains(cursor) }?.id ?? home
        }
    }

    /// На каких экранах стоят окна: только на главном — или на всех.
    static func windows(mode: NotchScreenMode, screens: [ScreenSlot]) -> [CGDirectDisplayID] {
        guard mode != .notched else { return home(screens).map { [$0] } ?? [] }
        return screens.map(\.id)
    }

    /// С границами включительно. Курсор, упёртый в верхнюю кромку, даёт `y`,
    /// равный `maxY`, а `CGRect.contains` верхнюю границу не включает:
    /// курсор у самой чёлки не принадлежал бы ни одному экрану.
    private static func contains(_ frame: CGRect, _ point: CGPoint) -> Bool {
        point.x >= frame.minX && point.x <= frame.maxX
            && point.y >= frame.minY && point.y <= frame.maxY
    }
}

/// Решает, на каких экранах стоят окна острова и какое из них главное.
///
/// Сами окна держит `NotchWindowHost`. Здесь — только выбор: он зовётся
/// десять раз в секунду и почти всегда отвечает «ничего не менять».
final class NotchScreens {
    private var mode: NotchScreenMode?
    private(set) var home: CGDirectDisplayID?
    /// Зоны раскрытия у полосок на чужих экранах.
    private var foreignTriggers: [CGRect] = []

    /// Расставить окна. `force` — экраны перестроились или поменялись размеры
    /// панелей: пересобрать всё.
    func place(mode: NotchScreenMode, host: NotchWindowHost, isBusy: Bool, force: Bool = false) {
        let force = force || mode != self.mode
        self.mode = mode
        let cursor = NSEvent.mouseLocation
        if !force, isSettled(mode: mode, host: host, cursor: cursor, isBusy: isBusy) { return }

        let screens = NSScreen.screens
        let slots = screens.map(NotchGeometry.slot(of:))
        guard let target = NotchScreenChoice.host(
            mode: mode,
            screens: slots,
            cursor: cursor,
            current: host.activeID,
            isBusy: isBusy
        ) else { return }
        home = NotchScreenChoice.home(slots)
        foreignTriggers = slots.filter { $0.id != home }.map(\.trigger)

        if force {
            let ids = Set(NotchScreenChoice.windows(mode: mode, screens: slots))
            host.rebuild(
                screens: screens.filter { ids.contains(NotchGeometry.displayID(of: $0)) },
                handles: mode == .all ? ids.subtracting([home].compactMap { $0 }) : [],
                active: target
            )
        } else {
            host.activate(target)
        }
    }

    /// Главный ли это экран.
    func isHome(_ id: CGDirectDisplayID) -> Bool { id == home }

    /// Пересчитывать нечего: так проходит почти каждый тик.
    private func isSettled(mode: NotchScreenMode, host: NotchWindowHost, cursor: CGPoint, isBusy: Bool) -> Bool {
        switch mode {
        case .notched:
            return true
        case .cursor:
            guard let frame = host.geometry?.screen.frame else { return false }
            return isBusy || frame.insetBy(dx: -1, dy: -1).contains(cursor)
        case .all:
            guard let current = host.activeID else { return false }
            if isBusy { return true }
            return current == home && !foreignTriggers.contains { $0.contains(cursor) }
        }
    }
}
