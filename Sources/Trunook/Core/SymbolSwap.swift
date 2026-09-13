import SwiftUI

/// Смена значка по состоянию — перетеканием, а не скачком.
///
/// Значков, которые меняются от состояния, в приложении почти три десятка:
/// пуск и пауза, микрофон и перечёркнутый микрофон, таймер и секундомер.
/// Скачок одной картинки в другую глаз читает как мигание, и понять, что
/// нажатие сработало, можно только перечитав значок.
///
/// Одним модификатором, а не `contentTransition` по месту, по той же причине,
/// что и `MotionPreference`: «уменьшить движение» должно выключать движение
/// везде разом.
///
/// На macOS 15 замена «волшебная»: у пар вроде `mic.fill` и `mic.slash.fill`
/// общая часть остаётся на месте, дорисовывается или стирается только черта.
/// На 14 — обычная замена, старый значок уходит вниз, новый приходит сверху.
/// При уменьшенном движении — просто наплыв.
///
/// `.animation(value:)` рядом нужна не только для самой замены, но и для
/// цвета: у тех же кнопок вместе со значком меняется тон, и без неё значок
/// перетекал бы, а цвет прыгал.
struct SymbolSwap<Value: Equatable>: ViewModifier {
    let value: Value
    @ObservedObject private var motion = MotionPreference.shared

    init(value: Value) {
        self.value = value
    }

    func body(content: Content) -> some View {
        content
            .contentTransition(motion.reduceMotion ? .opacity : Self.replace)
            .animation(.snappy, value: value)
    }

    private static var replace: ContentTransition {
        if #available(macOS 15, *) {
            return .symbolEffect(.replace.magic(fallback: .downUp.byLayer))
        }
        return .symbolEffect(.replace)
    }
}

/// Шеврон раскрытия: поворачивается, а не меняется на другой значок.
///
/// `chevron.right` и `chevron.down` — одна и та же стрелка, и замена
/// перерисовкой выглядела бы как два разных значка по очереди. Поворот
/// говорит ровно то, что происходит: раздел открылся.
struct DisclosureTurn: ViewModifier {
    let isOpen: Bool
    /// На сколько градусов поворачивать: 90 для «вправо → вниз»,
    /// 180 для «вниз → вверх».
    let degrees: Double
    @ObservedObject private var motion = MotionPreference.shared

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(isOpen ? degrees : 0))
            .animation(motion.reduceMotion ? nil : .snappy, value: isOpen)
    }
}

extension View {
    /// Смена значка перетеканием. `value` — то, от чего значок зависит;
    /// обычно само имя символа.
    func symbolSwap<Value: Equatable>(_ value: Value) -> some View {
        modifier(SymbolSwap(value: value))
    }

    func disclosureTurn(_ isOpen: Bool, degrees: Double = 90) -> some View {
        modifier(DisclosureTurn(isOpen: isOpen, degrees: degrees))
    }
}
