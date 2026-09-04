import CoreGraphics
import Foundation

/// Одна бумажка: всё, чем она отличается от соседних, решено заранее.
///
/// Полёт считается из времени, а не хранится: `@State` в этом тулчейне
/// недоступен, а вид, перерисовывающийся шестьдесят раз в секунду, тем более
/// не место для накопленной скорости. Тот же приём, что у `MarqueeText`.
struct ConfettiPiece: Equatable {
    /// Направление вылета в радианах. Ноль — вправо, положительное — вниз:
    /// разлетаться вверх бумажкам некуда, чёлка и так прижата к кромке экрана.
    let angle: Double
    /// Начальная скорость, точек в секунду.
    let speed: Double
    let size: CGSize
    /// Оборотов в секунду.
    let spin: Double
    /// Цвет берётся по номеру: сам цвет — дело вёрстки, а не расчёта.
    let colorIndex: Int
    /// Задержка вылета. Без неё все шестьдесят бумажек выходят одним диском,
    /// и залп читается кольцом, а не залпом.
    let delay: Double
}

/// Короткий залп конфетти из-под чёлки.
///
/// Считается целиком из времени и потому проверяется тестом: разброс, сроки
/// и затухание — числа, а не то, что видно только глазом на живой машине.
enum Confetti {
    /// Пара секунд, как и просили. Дольше — это уже не поздравление,
    /// а помеха работе.
    static let duration: TimeInterval = 2.0

    /// Ускорение вниз, точек в секунду за секунду.
    private static let gravity: Double = 760

    /// Сколько бумажек. Девяносто: шестидесяти на ширину экрана не хватало —
    /// залп рассыпался редким горохом. Отрисовку это не грузит, потому что
    /// рисует их один `Canvas`, а не девяносто отдельных видов.
    static let count = 90

    /// Разброс от вертикали вниз, в радианах. Восемьдесят градусов в каждую
    /// сторону: у`же — струя, шире — бумажки уходят вдоль самой кромки экрана
    /// и пропадают, не показавшись.
    private static let spread: Double = 80 * .pi / 180

    static func pieces(count: Int = Confetti.count, seed: UInt64 = 0x5EED) -> [ConfettiPiece] {
        var random = SeededGenerator(seed: seed)
        return (0 ..< count).map { index in
            // Веер раскладывается по порядку, а случайность только смещает
            // внутри своей доли: чистый случай на шестидесяти бумажках
            // оставляет проплешины, и залп выходит клочковатым.
            let share = (Double(index) + Double.random(in: 0 ... 1, using: &random))
                / Double(count)
            return ConfettiPiece(
                angle: .pi / 2 - spread + share * spread * 2,
                speed: Double.random(in: 240 ... 560, using: &random),
                size: CGSize(
                    width: Double.random(in: 6 ... 11, using: &random),
                    height: Double.random(in: 9 ... 16, using: &random)
                ),
                spin: Double.random(in: -2.6 ... 2.6, using: &random),
                colorIndex: Int.random(in: 0 ..< 5, using: &random),
                delay: Double.random(in: 0 ... 0.28, using: &random)
            )
        }
    }

    /// Где бумажка через `elapsed` секунд после залпа и насколько она видна.
    ///
    /// Смещение — в точках от места вылета, вниз положительное: так же считает
    /// экран, и вёрстке не придётся переворачивать ось.
    static func state(
        of piece: ConfettiPiece,
        elapsed: TimeInterval
    ) -> (offset: CGPoint, rotation: Double, opacity: Double)? {
        let time = elapsed - piece.delay
        guard time > 0, elapsed < duration else { return nil }

        let x = cos(piece.angle) * piece.speed * time
        let y = sin(piece.angle) * piece.speed * time + gravity * time * time / 2

        // Гаснут все разом к концу залпа, а не каждая по своему сроку:
        // разнобой на глаз читается как подвисание отрисовки.
        let fade = 0.6
        let left = duration - elapsed
        let opacity = left < fade ? max(0, left / fade) : 1

        return (CGPoint(x: x, y: y), piece.spin * time * 2 * .pi, opacity)
    }
}

/// Генератор с зерном: тот же залп при том же зерне.
///
/// Нужен ради теста. Настоящий случай проверить нечем — «выглядит случайно»
/// не утверждение, — а с зерном проверяются вещи проверяемые: что бумажки
/// разлетаются в обе стороны, что ни одна не выходит за веер и что залп
/// заканчивается в срок.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Нулевое зерно у splitmix64 законно, но начинать с него незачем:
        // первые числа последовательности от нуля заметно тусклее.
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
