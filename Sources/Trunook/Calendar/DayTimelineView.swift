import SwiftUI

/// Дела дня шкалой времени: часы столбиком слева, дела полосами справа.
///
/// Высота полосы — это длительность, и в этом вся разница со списком:
/// получасовая встреча вдвое ниже часовой, пустой промежуток между ними
/// виден пустым местом, а две одновременные стоят рядом столбцами, а не одна
/// под другой.
///
/// Размер приходит снаружи, а не выводится из содержимого. Правило общее
/// на все панели выреза: высокое содержимое растит `ZStack`, фигура тянется
/// за ним, и панель вылезает вверх поверх соседей.
struct DayTimelineChart: View {
    let timeline: DayTimeline
    let items: [CalendarItem]
    /// Место под шкалу целиком, включая колонку часов и строку дел на день.
    let size: CGSize
    /// Высота одного часа. Панель держит её постоянной и прокручивает шкалу,
    /// плитка — вписывает окно целиком: прокрутка внутри плитки спорила бы
    /// со свайпами по самому вырезу.
    let hourHeight: CGFloat
    var scrolls: Bool = true
    /// Пустое место в конце прокрутки — под кнопкой, лежащей поверх шкалы.
    /// Без него последняя полоса дня осталась бы под ней навсегда: та же
    /// причина, по которой место оставлено под кнопкой в списке заметок.
    var bottomInset: CGFloat = 0
    /// Нажатие по полосе. `nil` — шкала только показывает (плитка).
    var onOpen: ((CalendarItem) -> Void)?

    /// Колонка часов. Уже строки списка: в ней стоит один-два знака.
    static var gutter: CGFloat { NotchStyle.scaled(20) }
    /// Между колонкой часов и полосами.
    private static let gutterGap: CGFloat = 4
    /// Между столбцами одновременных дел.
    private static let laneGap: CGFloat = 2
    /// Ниже этой высоты полоса перестаёт быть полосой и становится чертой.
    private static let minimumBlockHeight: CGFloat = 6
    /// С какой высоты в полосе помещается название.
    ///
    /// Ниже неё название не прячется само, а режется пополам: строка выше
    /// полосы, и обрезка приходится посередине букв. Поймано снимком
    /// плитки — в панели, где час высотой в тридцать четыре точки, этого
    /// случая нет вовсе.
    ///
    /// Порог держит самая мелкая строка приложения — девять пунктов:
    /// час на вписанной шкале плитки выходит около одиннадцати точек,
    /// и пропусти мы этот случай, в плитке не осталось бы ни одного
    /// названия вовсе.
    private static let titleShowsFrom: CGFloat = 11
    /// С какой высоты название набирается обычным кеглем строки.
    private static let roomyTitleFrom: CGFloat = 14
    /// С какой высоты помещается ещё и время.
    private static let timeShowsFrom: CGFloat = 30
    static var allDayHeight: CGFloat { NotchStyle.scaled(18) }
    /// Поле над первой чертой.
    ///
    /// Подпись часа стоит на черте, то есть наполовину выше неё, — и первая
    /// подпись без этого поля срезается краем шкалы пополам. Поймано
    /// снимком: в вёрстке число стоит на своём месте, а видно от него
    /// нижнюю половину.
    private static var topInset: CGFloat { NotchStyle.font(9) / 2 + 1 }

    private var allDayItems: [CalendarItem] {
        timeline.allDay.compactMap { items.indices.contains($0) ? items[$0] : nil }
    }

    private var scaleHeight: CGFloat {
        max(0, size.height - (allDayItems.isEmpty ? 0 : Self.allDayHeight + 2))
    }

    private var contentHeight: CGFloat {
        scrolls
            ? Self.topInset + CGFloat(timeline.hours) * hourHeight + bottomInset
            : scaleHeight
    }

    /// Высота часа на самом деле: вписанная шкала растягивает или сжимает
    /// его под доставшееся место.
    private var pointsPerHour: CGFloat {
        scrolls
            ? hourHeight
            : max(1, scaleHeight - Self.topInset) / CGFloat(timeline.hours)
    }

    private var hourStep: Int {
        DayTimeline.hourStep(
            hours: timeline.hours,
            fitting: max(1, Int(contentHeight / NotchStyle.scaled(14)))
        )
    }

    private var laneWidth: CGFloat {
        max(0, size.width - Self.gutter - Self.gutterGap)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !allDayItems.isEmpty { allDayRow }
            if scrolls {
                // Прокрутка едет к тому часу, ради которого шкалу и открыли:
                // к «сейчас», а если день не сегодняшний — к первому делу.
                // Без этого день с одной встречей в 18:00 открывался бы
                // пустым утром, и человек решил бы, что дел нет вовсе.
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        scale
                    }
                    .frame(height: scaleHeight)
                    .onAppear { proxy.scrollTo(Self.anchor, anchor: .top) }
                }
            } else {
                scale.frame(height: scaleHeight)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    // MARK: - Шкала

    private var scale: some View {
        ZStack(alignment: .topLeading) {
            hourLines
            ForEach(timeline.blocks) { block in
                blockView(block)
            }
            nowLine
        }
        .frame(width: size.width, height: contentHeight, alignment: .topLeading)
    }

    /// Куда прокрутить шкалу при открытии.
    private static let anchor = "day-timeline-anchor"

    private var anchorMinute: Int {
        timeline.currentMinute ?? timeline.blocks.first?.startMinute ?? timeline.startMinute
    }

    /// Час, с которого начинать показ: сам час, а не минута внутри него, —
    /// иначе шкала встаёт так, что подпись часа осталась выше края.
    private var anchorHour: Int {
        max(timeline.startMinute, anchorMinute - anchorMinute % 60)
    }

    private var hourLines: some View {
        ForEach(Array(stride(from: timeline.startMinute, to: timeline.endMinute, by: 60)), id: \.self) { minute in
            let labelled = (minute - timeline.startMinute) / 60 % hourStep == 0
            HStack(alignment: .top, spacing: Self.gutterGap) {
                Text(DayTimeline.hourLabel(minute: minute))
                    .font(.system(size: NotchStyle.font(9), weight: .medium))
                    .monospacedDigit()
                    // Ступень пропущенной подписи прозрачная, а не убранная:
                    // место под колонку часов одно и то же при любом шаге.
                    .foregroundStyle(.white.opacity(labelled ? NotchStyle.tertiaryOpacity : 0))
                    .frame(width: Self.gutter, alignment: .trailing)
                    // Число сдвинуто вверх на половину своего роста: час —
                    // это черта, и подпись должна стоять на ней, а не висеть
                    // под ней.
                    .offset(y: -NotchStyle.font(9) / 2)
                Rectangle()
                    .fill(.white.opacity(labelled ? 0.10 : 0.05))
                    .frame(height: 1)
            }
            .frame(width: size.width, alignment: .leading)
            .offset(y: offset(of: minute))
            .id(minute == anchorHour ? Self.anchor : "hour-\(minute)")
        }
    }

    private func offset(of minute: Int) -> CGFloat {
        Self.topInset + CGFloat(minute - timeline.startMinute) / 60 * pointsPerHour
    }

    @ViewBuilder
    private func blockView(_ block: DayTimeline.Block) -> some View {
        if items.indices.contains(block.index) {
            let event = items[block.index]
            let width = max(0, (laneWidth - CGFloat(block.lanes - 1) * Self.laneGap) / CGFloat(block.lanes))
            let height = max(Self.minimumBlockHeight, CGFloat(block.minutes) / 60 * pointsPerHour)
            let named = height >= Self.titleShowsFrom
            Button { onOpen?(event) } label: {
                HStack(spacing: 4) {
                    // Полоска цвета календаря — то же, чем рабочая встреча
                    // отличается от личной в списке. Заливка взята тем же
                    // цветом, но приглушённой: цветное поле во всю ширину
                    // спорило бы с названием. Там, где названия нет, полоса
                    // красится целиком: иначе она читалась бы тенью, а не
                    // делом.
                    Capsule()
                        .fill(event.color)
                        .frame(width: 2.5)
                        .opacity(named ? 1 : 0)
                    VStack(alignment: .leading, spacing: 0) {
                        if named {
                            Text(event.title)
                                .font(.system(
                                    size: NotchStyle.font(height >= Self.roomyTitleFrom ? 10 : 9),
                                    weight: .medium
                                ))
                                .foregroundStyle(.white.opacity(NotchStyle.primaryOpacity))
                                .lineLimit(1)
                        }
                        if height >= Self.timeShowsFrom {
                            Text(CalendarPanel.span(event))
                                .font(.system(size: NotchStyle.font(9)))
                                .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, named ? 3 : 0)
                .padding(.vertical, named ? 1 : 0)
                .frame(width: width, height: height, alignment: .topLeading)
                .clipped()
                .background(
                    RoundedRectangle(cornerRadius: NotchStyle.artRadius, style: .continuous)
                        .fill(event.color.opacity(named ? 0.22 : 0.85))
                )
                // Без `contentShape` полоса нажималась бы только по буквам:
                // фон здесь рисует подложка, а не сама кнопка.
                .contentShape(RoundedRectangle(cornerRadius: NotchStyle.artRadius, style: .continuous))
            }
            .buttonStyle(PressableStyle())
            .disabled(onOpen == nil)
            .notchActionHint(t("Открыть событие"))
            .accessibilityLabel(event.title)
            .accessibilityValue(CalendarPanel.span(event))
            .offset(
                x: Self.gutter + Self.gutterGap + CGFloat(block.lane) * (width + Self.laneGap),
                y: offset(of: block.startMinute)
            )
        }
    }

    /// Черта текущего времени. Значением, а не веткой: у не сегодняшнего дня
    /// она прозрачная и стоит на месте — ветка пересобирала бы поддерево
    /// на каждом тике.
    private var nowLine: some View {
        let minute = timeline.currentMinute
        return HStack(spacing: 0) {
            Circle()
                .fill(Palette.calendar)
                .frame(width: 5, height: 5)
            Rectangle()
                .fill(Palette.calendar.opacity(0.75))
                .frame(height: 1)
        }
        .frame(width: size.width, alignment: .leading)
        .padding(.leading, Self.gutter + Self.gutterGap - 2.5)
        .offset(y: offset(of: minute ?? timeline.startMinute) - 2)
        .opacity(minute == nil ? 0 : 1)
        .accessibilityHidden(true)
    }

    // MARK: - Дела на весь день

    /// Своей строкой над шкалой: у дела на весь день часа нет, и полоса
    /// от края до края закрасила бы день целиком, ничего о нём не сказав.
    private var allDayRow: some View {
        HStack(spacing: 4) {
            ForEach(Array(allDayItems.enumerated()), id: \.offset) { _, event in
                HStack(spacing: 3) {
                    Circle().fill(event.color).frame(width: 4, height: 4)
                    Text(event.title)
                        .font(.system(size: NotchStyle.font(9.5)))
                        .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                        .lineLimit(1)
                }
                .padding(.horizontal, 5)
                .frame(height: Self.allDayHeight)
                .background(Capsule().fill(.white.opacity(0.08)))
            }
            Spacer(minLength: 0)
        }
        .frame(width: size.width, height: Self.allDayHeight, alignment: .leading)
        .clipped()
    }
}

/// Лента дня: та же шкала, положенная набок.
///
/// Для плитки в один ряд. Вертикальная шкала показала бы там два часа
/// из десяти, а лента отвечает на «как лежит день» целиком — ценой названий:
/// в полосу шириной в десяток точек слово не поместится никак, и полосы
/// здесь только цветные.
struct DayRibbon: View {
    let timeline: DayTimeline
    let items: [CalendarItem]
    let size: CGSize

    /// Строка подписей часов под лентой.
    private static var labelHeight: CGFloat { NotchStyle.scaled(12) }
    /// Уже этого полоса не видна вовсе.
    private static let minimumBlockWidth: CGFloat = 3

    private var trackHeight: CGFloat { max(6, size.height - Self.labelHeight) }

    private var hourStep: Int {
        DayTimeline.hourStep(
            hours: timeline.hours,
            // Под подпись часа — две цифры плюс воздух.
            fitting: max(1, Int(size.width / NotchStyle.scaled(26)))
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: NotchStyle.artRadius, style: .continuous)
                    .fill(.white.opacity(0.07))
                ticks
                ForEach(timeline.blocks) { block in
                    blockView(block)
                }
                nowLine
            }
            .frame(width: size.width, height: trackHeight)
            labels
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func x(of minute: Int) -> CGFloat {
        CGFloat(timeline.fraction(of: minute)) * size.width
    }

    private var hourMarks: [Int] {
        Array(stride(from: timeline.startMinute, through: timeline.endMinute, by: 60 * hourStep))
    }

    private var ticks: some View {
        ForEach(hourMarks, id: \.self) { minute in
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(width: 1, height: trackHeight)
                .offset(x: min(x(of: minute), size.width - 1))
        }
    }

    @ViewBuilder
    private func blockView(_ block: DayTimeline.Block) -> some View {
        if items.indices.contains(block.index) {
            let event = items[block.index]
            let left = x(of: block.startMinute)
            let width = max(Self.minimumBlockWidth, x(of: block.endMinute) - left)
            // Одновременные дела делят высоту ленты, а не ложатся друг
            // на друга: наложение читалось бы как одно дело подлиннее.
            let height = max(2, (trackHeight - CGFloat(block.lanes - 1)) / CGFloat(block.lanes))
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(event.color.opacity(0.85))
                .frame(width: min(width, max(0, size.width - left)), height: height)
                .offset(x: left, y: CGFloat(block.lane) * (height + 1))
                .accessibilityLabel(event.title)
                .accessibilityValue(CalendarPanel.span(event))
        }
    }

    private var nowLine: some View {
        let minute = timeline.currentMinute
        return Rectangle()
            .fill(Palette.calendar)
            .frame(width: 1.5, height: trackHeight)
            .offset(x: min(x(of: minute ?? timeline.startMinute), size.width - 1.5))
            .opacity(minute == nil ? 0 : 1)
            .accessibilityHidden(true)
    }

    private var labels: some View {
        ZStack(alignment: .topLeading) {
            ForEach(hourMarks, id: \.self) { minute in
                Text(DayTimeline.hourLabel(minute: minute))
                    .font(.system(size: NotchStyle.font(9)))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                    .fixedSize()
                    // Подпись стоит под своей чертой, а последняя прижата
                    // к правому краю: иначе она вылезает за плитку и режется.
                    .offset(x: max(0, min(x(of: minute) - 3, size.width - NotchStyle.scaled(14))))
            }
        }
        .frame(width: size.width, height: Self.labelHeight, alignment: .topLeading)
        .clipped()
        .accessibilityHidden(true)
    }
}
