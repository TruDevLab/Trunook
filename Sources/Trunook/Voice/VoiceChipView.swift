import SwiftUI

/// Мини-вид голосового захода: полоса высотой с чёлку.
///
/// Панель при голосовом вопросе **не раскрывается** намеренно: она закрыла бы
/// то, с чем человек работает, а смотреть в неё незачем — ответ звучит.
/// Полоса остаётся ровно затем, чтобы было видно три вещи: что тебя слышат,
/// что происходит сейчас, и чем это оборвать.
///
/// Слева — живая шкала громкости. Она здесь не для красоты: свечение
/// светилось бы одинаково и при говорящем человеке, и при занятом чужим
/// приложением микрофоне. Шкала отвечает на «слышат ли меня» — вопрос,
/// который возникает первым, когда ответа нет дольше обычного.
///
/// Справа — кнопка, обрывающая заход. Отдельной кнопкой, а не нажатием
/// по всей полосе: полоса открывает панель, а кнопка, вложенная в область
/// с общим нажатием, отбирала бы у неё попадания.
struct VoiceChipView: View {
    let phase: VoiceSession.Phase
    /// Громкость от нуля до единицы. В фазах ожидания и ответа не читается.
    let level: Double
    let metrics: NotchMetrics
    /// Оборвать заход.
    let onStop: () -> Void

    @ObservedObject private var motion = MotionPreference.shared

    /// Сколько столбиков в шкале.
    private static let barCount = 4
    private static let barWidth: CGFloat = 3.5
    private static let barSpacing: CGFloat = 3
    /// Высота самого низкого столбика: шкала при тишине не должна пропадать
    /// вовсе — исчезнувшая шкала читается как отключившийся микрофон.
    private static let barMinHeight: CGFloat = 5
    /// Потолок шкалы. Мерится от высоты чёлки, а не подбирается на глаз:
    /// столбики в шесть точек на полосе в тридцать две читаются четырьмя
    /// точками, а не шкалой, — это и было первым, что показал снимок.
    private static let barMaxHeight: CGFloat = 17
    /// Какую долю шкалы занимают столбики в полной тишине.
    private static let quietFloor: Double = 0.45

    private static var scaleWidth: CGFloat {
        CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
    }

    /// Запас вокруг содержимого в боковой полосе.
    ///
    /// Учитывает вогнутый уголок формы: тело острова начинается не от края,
    /// а отступив на радиус скругления, — то же соображение, что в `ChipView`.
    private static let sideMargin: CGFloat = 26

    /// Ширина боковой полосы. Одна и та же слева и справа: остров обязан
    /// оставаться отцентрованным по аппаратному вырезу, иначе он перестанет
    /// его закрывать.
    ///
    /// Считается по самому широкому из того, что в полосы кладут, — кнопке.
    /// Шкала у́же, и мерить по ней значило бы обрезать кнопку.
    static var sideWidth: CGFloat {
        max(scaleWidth, NotchPanelButton.size) + sideMargin
    }

    static func width(metrics: NotchMetrics) -> CGFloat {
        metrics.notchWidth + 2 * sideWidth
    }

    var body: some View {
        HStack(spacing: 0) {
            side { indicator }

            // Зазор ровно по ширине аппаратного выреза.
            Spacer(minLength: 0)
                .frame(width: metrics.notchWidth)

            side { stopButton }
        }
        .frame(width: Self.width(metrics: metrics), height: metrics.notchHeight)
    }

    /// Содержимое центрируется в своей полосе — запас делится поровну между
    /// кромкой острова и краем выреза.
    private func side<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: Self.sideWidth)
    }

    // MARK: - Слева: что происходит

    /// Шкала громкости — и она же показывает фазу.
    ///
    /// Один вид на все три фазы, а не три разных: `if` в теле вида меняет его
    /// тождество, и SwiftUI пересобирает поддерево вместо того чтобы доиграть
    /// переход. На этом уже ловили отрыв острова от кромки при мурчании.
    /// Поэтому столбики стоят всегда, а фаза меняет только их высоту и цвет.
    private var indicator: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: motion.reduceMotion)) { context in
            HStack(spacing: Self.barSpacing) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    Capsule()
                        .fill(tint)
                        .frame(
                            width: Self.barWidth,
                            height: barHeight(index: index, at: context.date)
                        )
                }
            }
            .frame(height: Self.barMaxHeight)
        }
        .accessibilityLabel(phaseLabel)
    }

    /// Высота столбика.
    ///
    /// Пока слушаем — от громкости, с разбегом по столбикам: одинаковые
    /// читались бы как один толстый брусок, а не как шкала. Пока ждём
    /// и отвечаем — своя волна от времени: громкости в эти фазы нет вовсе,
    /// а неподвижная шкала выглядела бы зависшей.
    private func barHeight(index: Int, at date: Date) -> CGFloat {
        let span = Self.barMaxHeight - Self.barMinHeight
        let value: Double

        switch phase {
        case .listening:
            // Средние столбики выше крайних — так шкала читается как голос,
            // а не как ряд палок.
            let shape = index == 0 || index == Self.barCount - 1 ? 0.65 : 1.0
            // Основание есть даже в полной тишине: шкала, осевшая в четыре
            // точки, читается как отключившийся микрофон — то есть ровно
            // наоборот тому, что должна сообщать. Молчание — это низкие
            // столбики, а не их отсутствие.
            value = (Self.quietFloor + (1 - Self.quietFloor) * min(1, level * 1.3)) * shape
        case .thinking, .speaking:
            guard !motion.reduceMotion else {
                // Движение выключено — ровная шкала вполсилы: неподвижная,
                // но и не погасшая.
                return Self.barMinHeight + span * 0.5
            }
            let shift = Double(index) * 0.7
            let speed = phase == .speaking ? 6.0 : 2.5
            value = (sin(date.timeIntervalSinceReferenceDate * speed + shift) + 1) / 2
        }

        return Self.barMinHeight + span * CGFloat(min(1, max(0, value)))
    }

    /// Цвет тот же, что у свечения вокруг острова: голубой — слушаю,
    /// фиолетовый — думаю и отвечаю. Порознь они разошлись бы при первой
    /// же правке, поэтому берутся из одного места.
    private var tint: Color { VoiceGlow.tint(for: phase) }

    private var phaseLabel: String {
        switch phase {
        case .listening: return t("Слушаю")
        case .thinking: return t("Модель думает…")
        case .speaking: return t("Отвечаю")
        }
    }

    // MARK: - Справа: чем оборвать

    private var stopButton: some View {
        Button(action: onStop) {
            // Квадрат, а не крестик: крестик по всему приложению значит
            // «закрыть», а здесь речь не закрывают — её обрывают. Знак
            // остановки читается этим значением сразу и без подписи,
            // как на любом проигрывателе.
            Image(systemName: "stop.fill")
                .font(.system(size: NotchStyle.font(10), weight: .semibold))
                // Ступенью тусклее: та же плотность, что у крестиков
                // в шапках панелей. Разная у одного и того же значка
                // читалась бы как небрежность.
                .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                .frame(width: NotchPanelButton.size, height: NotchPanelButton.size)
                // Без этого кнопка нажималась бы только по самим глифам:
                // фон у неё свой не нарисован, а попадать надо во всю область.
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .notchHint(stopHint)
    }

    private var stopHint: String {
        switch phase {
        case .listening: return t("Не слушать")
        case .thinking: return t("Отменить вопрос")
        case .speaking: return t("Замолчать")
        }
    }
}

/// Свечение вокруг острова во время голосового захода.
///
/// Цвета живут здесь, а не в вёрстке: их спрашивают двое — само свечение
/// и шкала в мини-виде, — и разойтись им негде, пока место одно.
enum VoiceGlow {
    static func tint(for phase: VoiceSession.Phase) -> Color {
        switch phase {
        // Слушаю — голубой: тот же цвет, которым в приложении помечено всё
        // входящее, от буфера обмена до нагрузки.
        case .listening: return Palette.cyan
        // Думаю и отвечаю — цвет модели. Разными их делать не стали:
        // ожидание и ответ — одна и та же работа модели, и смена цвета
        // посреди неё читалась бы как смена занятия.
        case .thinking, .speaking: return Palette.assistant
        }
    }

    /// Насколько сильно светить.
    static func strength(for phase: VoiceSession.Phase, level: Double) -> Double {
        switch phase {
        // Пока слушаем — свечение дышит вместе с голосом. Это второй, помимо
        // шкалы, ответ на «слышат ли меня», и заметен он краем глаза, когда
        // на вырез не смотрят.
        case .listening: return 0.55 + 0.35 * min(1, level * 1.3)
        case .thinking: return 0.6
        case .speaking: return 0.8
        }
    }

    /// Слои свечения: от плотного у самой кромки до прозрачного по краю
    /// ореола.
    ///
    /// Тенями, а не размытыми обводками, и это третий подход к одному
    /// и тому же. Обводка с `blur` не годится дважды: тонкую полосу сильное
    /// размытие размазывает в ничто — ореола просто не видно; а широкая
    /// с недостаточным размытием оставляет плотную середину с резким краем,
    /// и слои читаются концентрическими кольцами. Тень же угасает наружу
    /// сама, а наложенные друг на друга тени складываются в один плавный
    /// ореол.
    ///
    /// Дальний слой уходит на `spread` точек в каждую сторону, и это
    /// не число из воздуха: окно выреза шире полосы на добрую сотню точек
    /// с каждого бока, а всё, что не влезло, окно обрезает — по краю пошла бы
    /// ровная линия среза вместо угасания. Держит это `окноВмещаетСвечение`.
    struct Layer {
        let radius: CGFloat
        let opacity: Double
    }

    /// Обводка, от которой расходятся тени.
    ///
    /// **Размывается прежде, чем от неё пойдут тени.** Резкая линия видна
    /// сама по себе, и вместо ореола вокруг острова получается чёткий
    /// контур с бледным свечением снаружи — свет читается обводкой, а это
    /// ровно то, чего не нужно. Размытый источник линии не оставляет,
    /// а тени от него идут те же.
    static let edgeWidth: CGFloat = 5
    static let edgeBlur: CGFloat = 6

    /// Плотность взята с запасом: тени идут от **размытого** источника,
    /// и света в них заметно меньше, чем было бы от резкой обводки.
    static let layers: [Layer] = [
        Layer(radius: 8, opacity: 1),
        Layer(radius: 20, opacity: 0.8),
        Layer(radius: 38, opacity: 0.55),
        Layer(radius: 64, opacity: 0.4),
    ]

    /// Насколько далеко уходит самый дальний слой.
    static var spread: CGFloat {
        layers.map(\.radius).max() ?? 0
    }
}
