import SwiftUI

/// Плитка «Шкала дня»: дела дня, размещённые во времени.
///
/// Вёрстки две, по числу рядов. В два ряда — та же шкала, что и в панели
/// календаря: часы колонкой слева, дела полосами. В один ряд — лента:
/// вертикальная шкала показала бы там два часа из десяти, а вопрос, ради
/// которого на неё смотрят, — «как лежит день целиком».
///
/// Отдельная плитка, а не представление у «Ближайших встреч»: у списка
/// встреч свой вопрос — «что дальше», и на него он честно отвечает строками.
/// Шкала отвечает на другой, и переключателя внутри плитки быть не должно:
/// раскладку главного экрана собирают один раз, а не переключают на ходу.
struct TimelineWidget: View {
    let widget: HomeWidget
    @ObservedObject var planner: CalendarPlanner
    let actions: HomeActions

    /// Высота часа, при которой в получасовой полосе помещается название.
    ///
    /// Полчаса — это половина часа, а названию нужно одиннадцать точек:
    /// отсюда двадцать две. Плитка берёт столько часов, сколько влезает
    /// с такой высотой, — и показывает часть дня с названиями вместо всего
    /// дня штрих-кодом. Что не поместилось, считается и пишется числом
    /// в подписи.
    private static var namedHourHeight: CGFloat { NotchStyle.scaled(22) }

    private var inner: CGSize { HomeTile<EmptyView>.inner(widget.size) }
    private var captionHeight: CGFloat { NotchStyle.scaled(14) }

    /// Место под сам рисунок: плитка без подписи.
    private var chartSize: CGSize {
        CGSize(width: inner.width, height: max(0, inner.height - captionHeight - 2))
    }

    var body: some View {
        HomeTile(widget: widget, onTap: actions.openCalendar, hint: t("Открыть календарь")) {
            // Такт в полминуты — им живёт черта «сейчас». Чаще незачем:
            // минута на шкале в десяток точек высотой не видна вовсе.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let timeline = DayTimeline.make(
                    items: planner.events,
                    day: planner.day,
                    now: context.date
                )
                let shown = widget.size.rows == 1 ? timeline : timeline.limited(to: visibleHours)
                VStack(alignment: .leading, spacing: 2) {
                    HomeCaption(
                        kind: widget.kind,
                        title: Self.title(planner.day, now: context.date),
                        trailing: trailing(shown, of: timeline)
                    )
                    chart(shown)
                }
            }
        }
        // Разметку дня планировщик держит для открытого дня: открываем его
        // здесь, иначе после листания в календаре плитка показала бы тот
        // день, на котором календарь закрыли. Так же поступает «Месяц».
        .onAppear { planner.open() }
    }

    /// Сколько часов помещается в плитку с читаемой высотой часа.
    /// Не меньше наименьшего окна шкалы: у совсем низкой плитки выбора нет.
    private var visibleHours: Int {
        max(
            DayTimeline.minimumSpan / 60,
            Int(chartSize.height / Self.namedHourHeight)
        )
    }

    @ViewBuilder
    private func chart(_ timeline: DayTimeline) -> some View {
        if widget.size.rows == 1 {
            DayRibbon(timeline: timeline, items: planner.events, size: chartSize)
        } else {
            DayTimelineChart(
                timeline: timeline,
                items: planner.events,
                size: chartSize,
                // Час вписывается в плитку целиком: окно уже укорочено
                // до того, что сюда влезет.
                hourHeight: chartSize.height / CGFloat(timeline.hours),
                // Плитка не прокручивается: свайп по вырезу занят
                // перелистыванием, и прокрутка внутри плитки спорила бы
                // с ним.
                scrolls: false,
                onOpen: actions.openItem
            )
        }
    }

    /// Справа в подписи — окно шкалы, чтобы было видно, какую часть дня
    /// показывают, и сколько дел осталось за окном. Пустой день говорит
    /// об этом словом: пустая шкала с границами читается как
    /// «не загрузилось».
    private func trailing(_ shown: DayTimeline, of full: DayTimeline) -> String {
        guard !planner.events.isEmpty else { return t("свободно") }
        let range = DayTimeline.rangeLabel(from: shown.startMinute, to: shown.endMinute)
        let hidden = shown.hidden(from: full)
        return hidden > 0 ? range + "  +\(hidden)" : range
    }

    /// «Сегодня» или дата: плитка показывает открытый в календаре день,
    /// а он почти всегда сегодняшний.
    static func title(_ day: Date, now: Date, calendar: Calendar = .current) -> String {
        calendar.isDate(day, inSameDayAs: now)
            ? t("Сегодня")
            : CalendarPanel.dayLabel(day)
    }
}
