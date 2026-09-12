import CoreGraphics
import Foundation

/// Где стоят кружки быстрого доступа и в какой из них сейчас метит рука.
///
/// Отдельно от вёрстки и без обращений к SwiftUI: место кружка и попадание
/// в него — тригонометрия, а не рисунок. Ошибка в знаке угла здесь выглядит
/// как «кольцо разворачивается наизнанку», а ошибка в отборе — как «нажимается
/// не то, на что показываешь»; и то и другое ловится тестом, а живой рукой —
/// только случайно.
///
/// Отсчёт ведётся **вниз от нижней кромки чёлки**: кружки веером под ней,
/// вверх им расти некуда — там кромка экрана.
enum QuickRingLayout {
    /// Радиус веера: от чёлки до середины кружка.
    ///
    /// Наименьший. Настоящий считает `radius(count:)` — с ростом списка
    /// веер расходится, иначе кружки налезают друг на друга.
    static let radius: CGFloat = 128
    /// Поперечник кружка.
    static let circle: CGFloat = 42
    /// Веер идёт от 168° (слева) до 12° (справа).
    ///
    /// Не от 180° до 0°: там кружки встали бы вровень с чёлкой, то есть
    /// в самой кромке экрана, где их наполовину срезало бы. Дюжина градусов
    /// с каждой стороны опускает крайние ровно настолько, чтобы они целиком
    /// оказались под кромкой.
    static let startAngle: CGFloat = 168
    static let endAngle: CGFloat = 12

    /// Мёртвая зона у самой чёлки.
    ///
    /// Пока рука не отошла от места нажатия, не выбрано ничего: иначе кольцо
    /// выбирало бы кружок в тот же миг, когда появилось, — по дрожанию
    /// пальца на кнопке.
    static let deadZone: CGFloat = 44

    /// Радиус под такое число кружков.
    ///
    /// Веер расходится, когда список растёт. Углы делятся между кружками
    /// поровну, а с ними убывает и расстояние между серединами: на восьми
    /// оно 49 точек, на одиннадцати было бы 35 при поперечнике 42 — кружки
    /// налезли бы друг на друга на треть. Радиус поэтому не число, а расчёт
    /// от состава: кружки в самом тесном случае касаются, но не находят.
    ///
    /// Ниже `radius` веер не сжимается: на коротком списке разъезжаться
    /// ему некуда и незачем.
    static func radius(count: Int) -> CGFloat {
        guard count > 2 else { return radius }
        let step = (startAngle - endAngle) / CGFloat(count - 1) * .pi / 180
        return max(radius, circle / (2 * sin(step / 2)))
    }

    /// Смещения середин кружков от нижней кромки чёлки. `y` растёт **вниз**.
    static func offsets(count: Int) -> [CGPoint] {
        guard count > 0 else { return [] }
        let radius = self.radius(count: count)
        return (0..<count).map { index in
            let angle = self.angle(of: index, count: count) * .pi / 180
            return CGPoint(x: radius * cos(angle), y: radius * sin(angle))
        }
    }

    /// Угол кружка в градусах. Первый — слева: список читается слева направо,
    /// и веер, начинающийся справа, ставил бы первую функцию последней.
    static func angle(of index: Int, count: Int) -> CGFloat {
        guard count > 1 else { return 90 }
        let span = startAngle - endAngle
        return startAngle - span * CGFloat(index) / CGFloat(count - 1)
    }

    /// В какой кружок метит рука. `point` — смещение курсора от нижней кромки
    /// чёлки, `y` вниз.
    ///
    /// Отбор **по направлению, а не по попаданию в круг**. Так работает всякое
    /// круговое меню, и не из щедрости: держа кнопку, человек ведёт руку
    /// широким движением, а не целится — попадание требовало бы точности,
    /// которой при зажатой кнопке нет. Достаточно показать в сторону кружка,
    /// отойдя от чёлки.
    static func index(at point: CGPoint, count: Int) -> Int? {
        guard count > 0 else { return nil }
        // Вверх от чёлки кружков нет вовсе — там кромка экрана.
        guard point.y > 0 else { return nil }
        guard hypot(point.x, point.y) >= deadZone else { return nil }
        let angle = atan2(point.y, point.x) * 180 / .pi
        let span = startAngle - endAngle
        let step = count > 1 ? span / CGFloat(count - 1) : span
        var best: Int?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for index in 0..<count {
            let distance = abs(angle - self.angle(of: index, count: count))
            guard distance < bestDistance else { continue }
            bestDistance = distance
            best = index
        }
        // Половина шага в каждую сторону — ровно столько, сколько кружку
        // принадлежит.
        //
        // Под чёлкой это покрывает почти всё: у крайних кружков сектор
        // уходит за веер до самой кромки экрана, и это верно — рука,
        // показывающая левее левого кружка, метит именно в него.
        // **Передумать поэтому возвращаются к чёлке**, в мёртвую зону,
        // а не уводят руку вбок.
        return bestDistance <= step / 2 ? best : nil
    }

    /// Сколько места занимает веер вместе с кружками.
    static func size(count: Int) -> CGSize {
        let radius = self.radius(count: count)
        let widest = radius * cos(endAngle * .pi / 180)
        return CGSize(width: 2 * widest + circle, height: radius + circle / 2)
    }
}

/// Открыто ли кольцо и куда метит рука.
///
/// Общий объект, а не значение в теле вида: `@State` в этом тулчейне
/// недоступен, а признак нужен и вёрстке, и расчёту размера, и контроллеру.
final class QuickRing: ObservableObject {
    @Published private(set) var isOpen = false
    /// Номер кружка под рукой. `nil` — рука между кружками или у самой чёлки.
    @Published private(set) var highlighted: Int?

    /// До какого мгновения нажатие по чёлке считается своим.
    ///
    /// Кольцо и раскрытие панели делят одно и то же нажатие: панель
    /// раскрывается по отпусканию, и без этого кольцо выбирало бы функцию,
    /// а следом за ней раскрывалась бы ещё и панель. Заведомо больше, чем
    /// шаг опроса, — иначе отпускание успело бы проскочить мимо.
    private var tapSuppressedUntil = Date.distantPast

    func open() {
        guard !isOpen else { return }
        isOpen = true
        highlighted = nil
    }

    func move(to index: Int?) {
        guard isOpen, index != highlighted else { return }
        highlighted = index
    }

    /// Руку отпустили. Возвращает выбранное — если выбрано.
    @discardableResult
    func close() -> Int? {
        guard isOpen else { return nil }
        let picked = highlighted
        isOpen = false
        highlighted = nil
        tapSuppressedUntil = Date().addingTimeInterval(0.4)
        return picked
    }

    /// Нажатие по чёлке пришло от кольца, а не от человека, который просто
    /// щёлкнул.
    func swallowsTap() -> Bool {
        Date() < tapSuppressedUntil
    }
}
