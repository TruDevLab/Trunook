import SwiftUI

/// Раскладка шкалы времени: где на полосе стоит деление и какое оно.
///
/// Отдельно от вёрстки и без единого обращения к SwiftUI — чтобы правило
/// «куда уедет шкала, если протянуть её на столько-то точек» можно было
/// проверить тестом, а не глазами на снимке. Ошибка в знаке здесь выглядит
/// как «шкала едет не в ту сторону», и ловить её живой рукой дорого.
enum TimerDialLayout {
    /// Сколько точек занимает минута.
    ///
    /// Тринадцать выбраны от ширины панели: в четырёхстах точках содержимого
    /// умещается тридцать делений, то есть по четверти часа в каждую сторону
    /// от середины. Мельче — деления сливаются в гребёнку, крупнее — шкала
    /// перестаёт показывать, далеко ли до следующей пятиминутки.
    static let step: CGFloat = 13

    /// Одно деление.
    struct Tick: Equatable {
        /// Сколько это минут.
        let minutes: Int
        /// Где стоит по горизонтали, в точках от левого края полосы.
        let x: CGFloat
        /// Каждое пятое — длинное и с подписью.
        var isMajor: Bool { minutes % 5 == 0 }
    }

    /// Деления, попадающие в полосу шириной `width`, когда в её середине
    /// стоит `centerMinutes`.
    ///
    /// `centerMinutes` дробное намеренно: пока таймер идёт, остаток убывает
    /// непрерывно, и шкала должна ползти, а не прыгать раз в минуту.
    static func ticks(
        centerMinutes: Double,
        width: CGFloat,
        range: ClosedRange<Int>
    ) -> [Tick] {
        guard width > 0 else { return [] }
        let middle = width / 2
        // Половина полосы плюс одно деление про запас: крайнее должно
        // появляться до того, как въедет в кадр, иначе край мигает.
        let span = Int((middle / step).rounded(.up)) + 1
        let base = Int(centerMinutes.rounded())
        return (base - span...base + span).compactMap { minutes in
            guard range.contains(minutes) else { return nil }
            let x = middle + (CGFloat(minutes) - CGFloat(centerMinutes)) * step
            return Tick(minutes: minutes, x: x)
        }
    }

    /// Куда встанет шкала, если начать с `startMinutes` и протянуть её
    /// на `drag` точек.
    ///
    /// Знак обратный движению пальца, и это не описка: шкала едет **вместе**
    /// с рукой, как барабан. Тянут влево — деления уходят влево, и под
    /// серединой оказывается то, что было справа, то есть большее.
    ///
    /// Округление, а не дробная доля: шкала встаёт по делениям. Это и даёт
    /// щелчок с виброоткликом ровно на минуте — у непрерывного движения
    /// отмечать было бы нечего.
    static func minutes(
        from startMinutes: Int,
        drag: CGFloat,
        range: ClosedRange<Int>
    ) -> Int {
        let moved = Int((drag / step).rounded())
        return min(max(startMinutes - moved, range.lowerBound), range.upperBound)
    }
}

/// Что помнит шкала между кадрами перетаскивания.
///
/// Общий объект, а не значение в теле вида: `@State` в этом тулчейне
/// недоступен, а без памяти о том, где палец взялся за шкалу, перетаскивание
/// не собрать — `DragGesture` отдаёт смещение от начала жеста, и складывать
/// его не с чем.
///
/// Здесь же живёт отклик на проехавшее деление: виброотклик и щелчок — две
/// половины одного события, и разносить их по разным местам значило бы
/// когда-нибудь их рассинхронизировать.
final class TimerDialGrip {
    static let shared = TimerDialGrip()

    private let tick = TickPlayer()
    /// Значение в момент, когда палец взялся за шкалу. `nil` — не тянут.
    private var startMinutes: Int?

    /// Начало жеста. Вызывается на каждом кадре: `DragGesture` не сообщает
    /// отдельно о начале, и первый кадр приходится узнавать по пустой памяти.
    func begin(at minutes: Int) {
        guard startMinutes == nil else { return }
        startMinutes = minutes
    }

    var start: Int? { startMinutes }

    /// Шкалу держат прямо сейчас. По этому признаку накладка отказывается
    /// закрываться от ухода курсора: ход в пятнадцать минут выводит руку
    /// за края панели.
    var isHeld: Bool { startMinutes != nil }

    func end() { startMinutes = nil }

    /// Деление проехало под серединой.
    ///
    /// Звук отключается тем же переключателем, что и сигнал окончания:
    /// это звуки одной функции, и второй выключатель рядом с первым
    /// спрашивал бы человека дважды об одном.
    func passed() {
        Haptics.tap(.alignment)
        guard Settings.shared.timerSoundEnabled else { return }
        tick.play()
    }

    /// Резкая остановка — на выходе из приложения.
    func shutdown() {
        tick.shutdown()
    }
}

/// Шкала времени под цифрами.
///
/// Заменила ряд кнопок с готовыми длительностями. Кнопки отвечали ровно
/// на пять вопросов из возможных ста восьмидесяти — всё, что между ними,
/// набиралось «плюс минутой» по одному нажатию, — и занимали строку, ничего
/// не показывая о самом времени. Шкала показывает: видно, сколько осталось
/// до круглой пятиминутки и насколько выбранное больше соседнего.
///
/// Тянут её как барабан. Останов по делениям с виброоткликом и щелчком —
/// это то, чем колёсико отличается от ползунка: рука чувствует минуту,
/// не глядя на цифры.
struct TimerDial: View {
    /// Где стоит середина, в минутах. Дробное: пока время идёт, шкала ползёт.
    let centerMinutes: Double
    /// Границы. У таймера — от минуты до трёх часов, у секундомера снизу ноль,
    /// а сверху предела нет: он считает, пока его не остановят.
    let range: ClosedRange<Int>
    /// Что делать с выбранным значением. `nil` — шкалу не тянут: она идёт
    /// сама, и хвататься за неё не за что.
    let onScrub: ((Int) -> Void)?

    static let height: CGFloat = 30
    /// Докуда доросли длинные деления и метка середины.
    private static let majorHeight: CGFloat = 14
    private static let minorHeight: CGFloat = 6
    private static let topInset: CGFloat = 2
    /// Ширина растворения у краёв.
    ///
    /// Считается не от красоты, а от подписи: у крайней пятиминутки под
    /// делением стоит число, и растворение у́же его половины оставляет
    /// на кромке половину цифры. Сорока четырёх точек не хватило — на снимке
    /// у обоих краёв висели огрызки «10» и «40».
    private static let fade: CGFloat = 72

    private var grip: TimerDialGrip { .shared }

    var body: some View {
        Canvas { context, size in
            draw(in: context, size: size)
        }
        .frame(height: Self.height)
        .mask(fadeMask)
        .overlay(marker, alignment: .center)
        // Без этого шкала ловится только по нарисованным делениям: между
        // ними полоса прозрачна для попаданий, и жест рвётся на каждом зазоре.
        .contentShape(Rectangle())
        .gesture(drag)
        .accessibilityLabel(t("Сколько времени"))
        .accessibilityValue(tf("%d мин", Int(centerMinutes.rounded())))
    }

    // MARK: - Рисование

    private func draw(in context: GraphicsContext, size: CGSize) {
        for tick in TimerDialLayout.ticks(
            centerMinutes: centerMinutes,
            width: size.width,
            range: range
        ) {
            let height = tick.isMajor ? Self.majorHeight : Self.minorHeight
            let width: CGFloat = tick.isMajor ? 1.5 : 1
            let rect = CGRect(
                x: tick.x - width / 2,
                y: Self.topInset,
                width: width,
                height: height
            )
            context.fill(
                Path(roundedRect: rect, cornerRadius: width / 2),
                with: .color(.white.opacity(tick.isMajor ? 0.55 : 0.28))
            )
            guard tick.isMajor else { continue }
            // Подпись только у длинных: у каждой минуты числа сливаются
            // в сплошную строку и перестают читаться как числа.
            let label = context.resolve(
                Text("\(tick.minutes)")
                    .font(.system(size: NotchStyle.font(8.5), weight: .medium))
                    .foregroundStyle(.white.opacity(0.42))
            )
            context.draw(label, at: CGPoint(x: tick.x, y: Self.height - 6), anchor: .bottom)
        }
    }

    /// Метка середины — единственное цветное пятно в панели помимо шапки:
    /// она отвечает на «какое деление считается выбранным», и без цвета
    /// её пришлось бы искать среди тридцати одинаковых чёрточек.
    private var marker: some View {
        Capsule()
            .fill(Palette.timer)
            // Выше самого длинного деления: метка обязана быть заметно
            // не делением, иначе среди тридцати чёрточек её приходится
            // искать по цвету, а цвет — признак, который есть не у всех.
            .frame(width: 2.5, height: Self.majorHeight + Self.topInset + 4)
            .frame(height: Self.height, alignment: .top)
    }

    /// Края растворяются, а не обрубаются: обрезанная шкала читается
    /// обрезанной вёрсткой — той самой бедой, что ловили в проекте трижды, —
    /// а растворённая говорит «продолжается дальше».
    ///
    /// Доля считается от ширины содержимого панели, а не берётся на глаз:
    /// `LinearGradient` знает только доли, а растворение должно быть
    /// в точках, иначе оно поедет вместе с размером текста.
    private var fadeMask: some View {
        let edge = Self.fade / TimerPanel.contentWidth
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: edge),
                .init(color: .black, location: 1 - edge),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Жест

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard let onScrub else { return }
                grip.begin(at: Int(centerMinutes.rounded()))
                guard let start = grip.start else { return }
                let chosen = TimerDialLayout.minutes(
                    from: start,
                    drag: value.translation.width,
                    range: range
                )
                guard chosen != Int(centerMinutes.rounded()) else { return }
                grip.passed()
                onScrub(chosen)
            }
            .onEnded { _ in grip.end() }
    }
}
