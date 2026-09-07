import CoreGraphics
import Foundation
import Testing
@testable import Trunook

@Suite("Кольцо быстрого доступа")
struct QuickRingTests {
    private let count = 8

    /// Смещение курсора от нижней кромки чёлки под заданным углом.
    private func point(at degrees: CGFloat, distance: CGFloat = 130) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: distance * cos(radians), y: distance * sin(radians))
    }

    @Test("Кружков ровно столько, сколько функций")
    func числоКружков() {
        #expect(QuickRingLayout.offsets(count: count).count == count)
    }

    /// Список читается слева направо, и веер, начинающийся справа, ставил бы
    /// первую функцию последней.
    @Test("Первый кружок слева, последний справа")
    func порядокПоВееру() {
        let offsets = QuickRingLayout.offsets(count: count)
        #expect(offsets[0].x < 0)
        #expect(offsets[count - 1].x > 0)
        // По горизонтали идут строго слева направо.
        #expect(zip(offsets, offsets.dropFirst()).allSatisfy { $0.x < $1.x })
    }

    /// Вверх кружкам расти некуда — там кромка экрана.
    @Test("Все кружки лежат ниже чёлки")
    func всеПодЧёлкой() {
        #expect(QuickRingLayout.offsets(count: count).allSatisfy { $0.y > 0 })
    }

    @Test("Кружки стоят на одном расстоянии от чёлки")
    func одинРадиус() {
        for offset in QuickRingLayout.offsets(count: count) {
            #expect(abs(hypot(offset.x, offset.y) - QuickRingLayout.radius) < 0.01)
        }
    }

    /// Пока рука не отошла от места нажатия, не выбрано ничего: иначе кольцо
    /// выбирало бы кружок в тот же миг, когда появилось, — по дрожанию пальца.
    @Test("У самой чёлки не выбрано ничего")
    func мёртваяЗона() {
        #expect(QuickRingLayout.index(at: .zero, count: count) == nil)
        #expect(QuickRingLayout.index(at: point(at: 90, distance: 10), count: count) == nil)
        #expect(QuickRingLayout.index(at: point(at: 90, distance: 200), count: count) != nil)
    }

    @Test("Выбирается тот кружок, в сторону которого показывают")
    func отборПоНаправлению() {
        for index in 0..<count {
            let angle = QuickRingLayout.angle(of: index, count: count)
            #expect(QuickRingLayout.index(at: point(at: angle), count: count) == index)
        }
    }

    /// Держа кнопку, человек ведёт руку широким движением, а не целится:
    /// попадание точно в круг требовало бы точности, которой при зажатой
    /// кнопке нет. Достаточно показать в сторону — и на любом удалении.
    @Test("Направление важнее расстояния")
    func далекоТожеСчитается() {
        let angle = QuickRingLayout.angle(of: 3, count: count)
        #expect(QuickRingLayout.index(at: point(at: angle, distance: 60), count: count) == 3)
        #expect(QuickRingLayout.index(at: point(at: angle, distance: 400), count: count) == 3)
    }

    /// У крайних кружков сектор уходит за веер до самой кромки экрана,
    /// и это верно: рука, показывающая левее левого кружка, метит именно
    /// в него. Передумать поэтому возвращаются к чёлке, а не уводят руку вбок.
    @Test("За крайним кружком метят в него же")
    func заКраемВеера() {
        #expect(QuickRingLayout.index(at: point(at: 179), count: count) == 0)
        #expect(QuickRingLayout.index(at: point(at: 1), count: count) == count - 1)
    }

    /// Единственный способ передумать — вернуть руку к чёлке. Проверяется
    /// вместе с краями: если бы сектор кружка кончался раньше кромки, отмена
    /// случалась бы вбок сама собой, и человек терял бы выбор на ровном месте.
    @Test("Передумать можно только возвратом к чёлке")
    func отменаТолькоУЧёлки() {
        let angle = QuickRingLayout.angle(of: 4, count: count)
        #expect(QuickRingLayout.index(at: point(at: angle, distance: 300), count: count) != nil)
        #expect(QuickRingLayout.index(at: point(at: angle, distance: 20), count: count) == nil)
    }

    /// Вверх от чёлки кружков нет вовсе.
    @Test("Над чёлкой не выбрано ничего")
    func надЧёлкой() {
        #expect(QuickRingLayout.index(at: CGPoint(x: 0, y: -100), count: count) == nil)
        #expect(QuickRingLayout.index(at: CGPoint(x: 60, y: -60), count: count) == nil)
    }

    @Test("Пустое кольцо не выбирает ничего")
    func пустоеКольцо() {
        #expect(QuickRingLayout.index(at: point(at: 90), count: 0) == nil)
        #expect(QuickRingLayout.offsets(count: 0).isEmpty)
    }

    /// Кольцо и раскрытие панели делят одно нажатие: панель раскрывается
    /// по отпусканию, и без этого за выбранной функцией открывалась бы ещё
    /// и она.
    @Test("Отпускание кольца не раскрывает панель")
    func нажатиеНеПроходитДважды() {
        let ring = QuickRing()
        #expect(!ring.swallowsTap())
        ring.open()
        ring.move(to: 2)
        #expect(ring.close() == 2)
        #expect(ring.swallowsTap())
    }

    @Test("Закрытое кольцо ничего не выбирает и не глотает нажатий")
    func закрытоеНеВыбирает() {
        let ring = QuickRing()
        ring.move(to: 3)
        #expect(ring.highlighted == nil)
        #expect(ring.close() == nil)
        #expect(!ring.swallowsTap())
    }
}
