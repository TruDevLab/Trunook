import SwiftUI

/// Мини-календарь: месяц слева, дела выбранного дня справа.
///
/// Появился потому, что вырез до этого отвечал только на «что впереди
/// сегодня». Вопрос «а что в четверг» задавали Календарю — то есть уходили
/// из выреза целиком, в чужое окно поверх работы, ради одного взгляда.
///
/// Две половины, а не две панели: месяц без дня — сетка чисел, день без
/// месяца — список без места во времени. Их и смотрят вместе, водя по датам
/// и читая, что там.
struct CalendarPanel: View {
    @ObservedObject var planner: CalendarPlanner
    let metrics: NotchMetrics
    let onOpenEvent: (CalendarItem) -> Void
    let onCompose: () -> Void
    let onClose: () -> Void

    // MARK: - Размеры

    static var width: CGFloat { NotchStyle.scaled(620) }
    static let bodyPadding: CGFloat = NotchStyle.bottomPadding

    /// Ширина колонки с номерами недель.
    private static var weekNumberWidth: CGFloat { NotchStyle.scaled(22) }
    private static var cellWidth: CGFloat { NotchStyle.scaled(37) }
    private static var cellHeight: CGFloat { NotchStyle.scaled(25) }
    private static let cellSpacing: CGFloat = 2
    /// Ширина левой половины считается от сетки, а не задаётся числом:
    /// подобранная под нынешнюю клетку, она разошлась бы с ней при первой
    /// же правке размера.
    static var monthWidth: CGFloat {
        weekNumberWidth + 7 * cellWidth + 7 * cellSpacing
    }
    private static var headerHeight: CGFloat { NotchStyle.scaled(22) }
    private static var weekdayHeight: CGFloat { NotchStyle.scaled(15) }
    private static var gridHeight: CGFloat {
        CGFloat(CalendarMonth.rows) * cellHeight + CGFloat(CalendarMonth.rows - 1) * cellSpacing
    }

    /// Высота содержимого — по левой половине: она не меняется никогда,
    /// а правая тянется за ней. Считать по правой значило бы растить панель
    /// на дне с семью встречами и ронять на пустом.
    static var contentHeight: CGFloat {
        headerHeight + NotchStyle.gridSpacing + weekdayHeight + 4 + gridHeight
    }

    static var rowHeight: CGFloat { NotchStyle.scaled(34) }
    static var newEventSize: CGFloat { NotchStyle.scaled(30) }

    static func height(notchHeight: CGFloat) -> CGFloat {
        NotchStyle.height(notchHeight: notchHeight, contentHeight: contentHeight)
    }

    // MARK: - Тело

    var body: some View {
        NotchPanel(metrics: metrics, width: Self.width, bodyPadding: Self.bodyPadding) {
            NotchPanelTitle(symbol: "calendar", title: t("Календарь"), tint: Palette.calendar)
        } trailing: {
            NotchPanelButton(symbol: "xmark", hint: t("Закрыть"), action: onClose)
        } content: {
            HStack(alignment: .top, spacing: NotchStyle.scaled(14)) {
                monthSide.frame(width: Self.monthWidth)
                daySide.frame(maxWidth: .infinity)
            }
            .frame(height: Self.contentHeight)
        }
    }

    // MARK: - Месяц

    private var monthSide: some View {
        VStack(spacing: 0) {
            monthHeader
            Spacer().frame(height: NotchStyle.gridSpacing)
            weekdayRow
            Spacer().frame(height: 4)
            grid
        }
    }

    private var monthHeader: some View {
        HStack(spacing: 0) {
            arrow("chevron.left", hint: t("Прошлый месяц")) { planner.step(months: -1) }
            Text(CalendarMonth.title(of: planner.month))
                .font(.system(size: NotchStyle.rowFontSize, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
            arrow("chevron.right", hint: t("Следующий месяц")) { planner.step(months: 1) }
        }
        .frame(height: Self.headerHeight)
    }

    private func arrow(_ symbol: String, hint: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol)
                .font(.system(size: NotchStyle.font(10), weight: .semibold))
                .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                .frame(width: Self.headerHeight, height: Self.headerHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .notchHint(hint)
    }

    private var weekdayRow: some View {
        HStack(spacing: Self.cellSpacing) {
            // Колонка номеров недели своей подписи не имеет: «№» над числами
            // читается как ещё один день, а объяснять колонку, в которой
            // и так стоят числа от одного до пятидесяти двух, нечем.
            Color.clear.frame(width: Self.weekNumberWidth)
            ForEach(Array(CalendarMonth.weekdayTitles().enumerated()), id: \.offset) { _, title in
                Text(title)
                    .font(.system(size: NotchStyle.font(9.5), weight: .medium))
                    .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                    .frame(width: Self.cellWidth)
            }
        }
        .frame(height: Self.weekdayHeight)
        .accessibilityHidden(true)
    }

    private var grid: some View {
        VStack(spacing: Self.cellSpacing) {
            ForEach(planner.grid.weeks) { week in
                HStack(spacing: Self.cellSpacing) {
                    Text("\(week.number)")
                        .font(.system(size: NotchStyle.font(9), weight: .medium))
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(width: Self.weekNumberWidth, height: Self.cellHeight)
                        .accessibilityLabel(tf("Неделя %d", week.number))
                    ForEach(week.days) { day in
                        dayCell(day)
                    }
                }
            }
        }
        .frame(height: Self.gridHeight)
    }

    private func dayCell(_ day: CalendarMonth.Day) -> some View {
        let selected = planner.isSelected(day.date)
        let today = planner.isToday(day.date)
        return Button(action: { planner.select(day.date) }) {
            VStack(spacing: 1) {
                Text("\(day.number)")
                    .font(.system(
                        size: NotchStyle.font(11),
                        weight: selected || today ? .semibold : .regular
                    ))
                    .foregroundStyle(.white.opacity(number(selected: selected, inMonth: day.isInMonth)))
                // Точка под числом: день, в котором что-то есть. Своим ярусом,
                // а не подложкой под числом, — подложку уже занял выбор,
                // и два смысла на одной подложке различить было бы нечем.
                Circle()
                    .fill(Palette.calendar.opacity(planner.hasEvents(day.date) ? 0.9 : 0))
                    .frame(width: 3, height: 3)
            }
            .frame(width: Self.cellWidth, height: Self.cellHeight)
            // Роль сегмента, а не плитки: в покое клетка не рисует ничего.
            // Плиткой она рисовала подложку каждому из сорока двух чисел,
            // и сетка выходила стеной серых плашек — в ней не читалось
            // ни выбранного дня, ни границы месяца, ни точек под числами.
            // Подложка здесь значит ровно одно: этот день выбран.
            .surface(
                .segment,
                in: RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous),
                tint: Palette.calendar,
                lit: selected,
                glass: Surface.inNotch && selected
            )
            // Сегодняшнее число обведено, а не залито: заливка — это выбор,
            // и два разных смысла одной краской не показать. Обводка живёт
            // значением, а не веткой: невыбранный день получает прозрачную.
            .overlay(
                RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
                    .strokeBorder(Palette.calendar.opacity(today && !selected ? 0.55 : 0), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(Self.dayLabel(day.date))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func number(selected: Bool, inMonth: Bool) -> Double {
        if selected { return 1 }
        return inMonth ? NotchStyle.primaryOpacity : 0.3
    }

    // MARK: - День

    private var daySide: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Self.dayLabel(planner.day))
                .font(.system(size: NotchStyle.captionFontSize, weight: .semibold))
                .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                .frame(height: Self.headerHeight, alignment: .leading)
            ZStack(alignment: .bottomTrailing) {
                if planner.events.isEmpty {
                    emptyDay
                } else {
                    dayList
                }
                newEventButton
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyDay: some View {
        Text(t("В этот день ничего не назначено"))
            .font(.system(size: NotchStyle.font(11.5)))
            .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Список дня. Ближайшее дело выделено, и выделение живое: полминуты
    /// хватает, чтобы «через 3 мин» не превратилось во враньё, пока панель
    /// открыта, — а закрытая панель не стоит ни одного пробуждения.
    private var dayList: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let next = DayAgenda.nextIndex(in: planner.events, now: context.date)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: NotchStyle.rowSpacing) {
                    // По номеру, а не по записи: два вхождения одного
                    // повторяющегося события в один день делят идентификатор,
                    // и `ForEach` по нему показал бы одну строку вместо двух.
                    ForEach(Array(planner.events.enumerated()), id: \.offset) { index, event in
                        eventRow(event, isNext: index == next, now: context.date)
                    }
                    // Место под кнопкой в самой прокрутке: без него последняя
                    // строка осталась бы под стеклом навсегда.
                    Color.clear.frame(height: Self.newEventSize)
                }
            }
        }
    }

    /// Строка дела.
    ///
    /// Ближайшее выделено тремя признаками сразу, и это не перебор:
    /// подложка ярче, полоска слева толще, справа стоит «через 40 мин».
    /// Порознь каждый слаб — подложку не с чем сравнить, когда строка
    /// в списке одна; полоска у всех строк своя и разного цвета; подпись
    /// читается только если её найти глазами. Вместе они отвечают на «куда
    /// мне сейчас» с одного взгляда, а именно за этим в список дня и смотрят.
    private func eventRow(_ event: CalendarItem, isNext: Bool, now: Date) -> some View {
        Button(action: { onOpenEvent(event) }) {
            HStack(spacing: 8) {
                // Полоска цвета календаря — то, чем рабочая встреча отличается
                // от личной, не читая названия. У ближайшего она толще:
                // цвет тут занят смыслом «чей календарь», и выделять им же
                // ещё и «ближайшее» было бы двумя ответами одной краской.
                Capsule()
                    .fill(event.color)
                    .frame(width: isNext ? 4 : 3)
                    .padding(.vertical, isNext ? 3 : 5)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title)
                        .font(.system(
                            size: NotchStyle.rowFontSize,
                            weight: isNext ? .semibold : .medium
                        ))
                        .foregroundStyle(.white.opacity(
                            isNext ? 1 : NotchStyle.primaryOpacity
                        ))
                        .lineLimit(1)
                    Text(Self.span(event))
                        .font(.system(size: NotchStyle.captionFontSize))
                        .foregroundStyle(.white.opacity(
                            isNext ? NotchStyle.secondaryOpacity : NotchStyle.tertiaryOpacity
                        ))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isNext {
                    Text(DayAgenda.badge(for: event, now: now))
                        .font(.system(size: NotchStyle.captionFontSize, weight: .semibold))
                        .foregroundStyle(Palette.calendar)
                        .lineLimit(1)
                        // Цифры не дёргают строку на каждой смене минуты.
                        .monospacedDigit()
                }
                if event.link != nil {
                    Image(systemName: "video.fill")
                        .font(.system(size: NotchStyle.font(9)))
                        .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: Self.rowHeight)
            .surface(
                .row,
                in: RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous),
                tint: Palette.calendar,
                lit: isNext,
                glass: Surface.inNotch
            )
            .contentShape(RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .notchActionHint(t("Открыть событие"))
        // Диктору признак сообщается словами: подложку и толщину полоски
        // он не читает вовсе.
        .accessibilityValue(isNext ? DayAgenda.badge(for: event, now: now) : "")
    }

    /// Кнопка «плюс» — та же, что в списке заметок, и по той же причине:
    /// круг закрывает вчетверо меньше строк под собой, чем подпись, а сказать
    /// «Новое событие» есть чем — всплывающая плашка под чёлкой.
    private var newEventButton: some View {
        NotchTile(
            id: "calendar-new",
            radius: Self.newEventSize / 2,
            role: .tile,
            tint: Palette.calendar
        ) {
            Button(action: onCompose) {
                Image(systemName: "plus")
                    .font(.system(size: NotchStyle.font(15), weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: Self.newEventSize, height: Self.newEventSize)
                    .background(Circle().fill(.white.opacity(0.10)))
                    .overlay(Circle().strokeBorder(.white.opacity(0.28), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .notchHint(t("Новое событие"))
        }
        .fixedSize()
    }

    // MARK: - Записи времени

    /// «12 сентября, четверг».
    static func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Localization.shared.resolved.locale
        formatter.setLocalizedDateFormatFromTemplate("d MMMM EEEE")
        return formatter.string(from: date).capitalizedFirst
    }

    /// «14:00 – 15:00» или «весь день».
    static func span(_ event: CalendarItem) -> String {
        guard !event.isAllDay else { return t("весь день") }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let start = formatter.string(from: event.start)
        guard let end = event.end, end > event.start else { return start }
        return start + " – " + formatter.string(from: end)
    }
}
