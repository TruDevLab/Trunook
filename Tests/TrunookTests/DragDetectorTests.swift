import CoreGraphics
import Foundation
import Testing
@testable import Trunook

@Suite("Перетаскивание против нажатия")
struct DragDetectorTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    /// Ради этого всё и затевалось: пока человек просто нажимает, зона приёма
    /// файлов обязана оставаться прозрачной для мыши.
    @Test("Нажатие без движения перетаскиванием не считается")
    func нажатиеНеПеретаскивание() {
        let detector = DragDetector()
        let point = CGPoint(x: 100, y: 900)
        detector.update(isPressed: true, at: point, now: start)
        detector.update(isPressed: true, at: point, now: start.addingTimeInterval(0.1))
        detector.update(isPressed: false, at: point, now: start.addingTimeInterval(0.2))
        #expect(detector.isDragging == false)
    }

    @Test("Дрожь руки на месте порога не берёт")
    func дрожьНеСчитается() {
        let detector = DragDetector()
        detector.update(isPressed: true, at: CGPoint(x: 100, y: 900), now: start)
        detector.update(isPressed: true, at: CGPoint(x: 103, y: 902), now: start.addingTimeInterval(0.1))
        #expect(detector.isDragging == false)
    }

    @Test("Уход от точки нажатия — перетаскивание")
    func движениеСчитается() {
        let detector = DragDetector()
        var reported: [Bool] = []
        detector.onChange = { reported.append($0) }
        detector.update(isPressed: true, at: CGPoint(x: 100, y: 900), now: start)
        detector.update(isPressed: true, at: CGPoint(x: 140, y: 880), now: start.addingTimeInterval(0.1))
        #expect(detector.isDragging)
        #expect(reported == [true])
    }

    /// Файл роняют отпусканием кнопки. Сними признак ровно в этот миг —
    /// и рискуешь самим падением.
    @Test("После отпускания признак держится ещё немного")
    func запасПослеОтпускания() {
        let detector = DragDetector()
        detector.update(isPressed: true, at: CGPoint(x: 100, y: 900), now: start)
        detector.update(isPressed: true, at: CGPoint(x: 200, y: 700), now: start.addingTimeInterval(0.1))
        #expect(detector.isDragging)

        detector.update(isPressed: false, at: CGPoint(x: 200, y: 700), now: start.addingTimeInterval(0.2))
        #expect(detector.isDragging, "признак снят сразу — падение файла может не успеть")

        detector.update(isPressed: false, at: CGPoint(x: 200, y: 700), now: start.addingTimeInterval(1.0))
        #expect(detector.isDragging == false)
    }

    /// Перетаскивание тремя пальцами идёт без нажатой кнопки: держится
    /// только на событиях движения.
    @Test("Событие движения поднимает признак без нажатой кнопки")
    func тремяПальцами() {
        let detector = DragDetector()
        detector.note(now: start)
        #expect(detector.isDragging)

        // Пока события идут, признак живёт.
        detector.update(isPressed: false, at: .zero, now: start.addingTimeInterval(0.4))
        detector.note(now: start.addingTimeInterval(0.5))
        detector.update(isPressed: false, at: .zero, now: start.addingTimeInterval(0.9))
        #expect(detector.isDragging)

        // События кончились — признак гаснет сам.
        detector.update(isPressed: false, at: .zero, now: start.addingTimeInterval(1.2))
        #expect(detector.isDragging == false)
    }

    @Test("О смене сообщается один раз, а не на каждый тик")
    func сообщаетТолькоОСмене() {
        let detector = DragDetector()
        var reported: [Bool] = []
        detector.onChange = { reported.append($0) }
        detector.update(isPressed: true, at: CGPoint(x: 0, y: 0), now: start)
        for step in 1...5 {
            let time = start.addingTimeInterval(Double(step) * 0.1)
            detector.update(isPressed: true, at: CGPoint(x: 50 * step, y: 0), now: time)
        }
        detector.update(isPressed: false, at: CGPoint(x: 250, y: 0), now: start.addingTimeInterval(2))
        #expect(reported == [true, false])
    }
}
