import SwiftUI

/// Какое письмо открыто превью. Отдельным объектом, а не полем накладки:
/// накладка — перечисление без значений, а письмо должно пережить
/// перестройку вёрстки, пока его читают.
final class LetterPreviewModel: ObservableObject {
    @Published var notice: ExternalNotice?
}

/// Превью письма из плашки Trudaybook: от кого, тема, начало текста
/// и кнопки решения под ним.
///
/// Плашка о новом письме предлагала «Ответить» и «В архив» — решение
/// о письме, которого человек ещё не видел. Теперь на плашке «Открыть
/// в Trudaybook» и «Показать превью»; превью читается здесь же, а решения
/// принимаются в почте, где видно всё письмо и вся переписка.
struct LetterPreviewPanel: View {
    let notice: ExternalNotice?
    let metrics: NotchMetrics
    /// Кнопка из плашки, кроме самого превью, — «Открыть в Trudaybook».
    let onAction: (ExternalNotice, ExternalNotice.Action) -> Void
    let onClose: () -> Void

    private static var minimumWidth: CGFloat { NotchStyle.scaled(460) }

    static func width(notchWidth: CGFloat) -> CGFloat {
        max(
            minimumWidth,
            NotchStyle.width(
                fittingWing: NotchStyle.wingRow(buttons: 1),
                notchWidth: notchWidth,
                bodyPadding: NotchStyle.bottomPadding
            )
        )
    }

    private static var headerHeight: CGFloat { NotchStyle.scaled(38) }
    /// Текст письма — восемь строк, дальше прокрутка.
    private static var textHeight: CGFloat { NotchStyle.scaled(150) }
    private static var buttonHeight: CGFloat { NotchStyle.rowHeight }
    /// Ряд быстрых действий — ниже главной кнопки, мельче её.
    private static var quickHeight: CGFloat { NotchStyle.scaled(26) }

    /// Ряд быстрых действий место держит всегда: высота панели считается
    /// заранее, без письма в руках.
    static func height(notchHeight: CGFloat) -> CGFloat {
        NotchStyle.height(
            notchHeight: notchHeight,
            contentHeight: headerHeight + NotchStyle.gridSpacing + textHeight
                + NotchStyle.gridSpacing + quickHeight
                + NotchStyle.gridSpacing + buttonHeight
        )
    }

    var body: some View {
        NotchPanel(
            metrics: metrics,
            width: Self.width(notchWidth: metrics.notchWidth),
            bodyPadding: NotchStyle.bottomPadding
        ) {
            NotchPanelTitle(symbol: "envelope", title: notice?.source ?? t("Письмо"), tint: Palette.blue)
        } trailing: {
            NotchPanelButton(symbol: "xmark", hint: t("Закрыть"), action: onClose)
        } content: {
            VStack(alignment: .leading, spacing: NotchStyle.gridSpacing) {
                header
                text
                quickActions
                buttons
            }
        }
    }

    private var preview: ExternalNotice.LetterPreview? { notice?.preview }

    private var sender: String {
        if let from = preview?.from, !from.isEmpty { return from }
        return notice?.title ?? ""
    }

    private var subject: String {
        if let subject = preview?.subject, !subject.isEmpty { return subject }
        return t("Без темы")
    }

    private var body_: String {
        if let text = preview?.text, !text.isEmpty { return text }
        return t("Текст письма ещё не загружен — откройте его в почте.")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(sender)
                    .font(.system(size: NotchStyle.rowFontSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(NotchStyle.primaryOpacity))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let date = preview?.date, !date.isEmpty {
                    Text(date)
                        .font(.system(size: NotchStyle.captionFontSize))
                        .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                        .lineLimit(1)
                }
            }
            Text(subject)
                .font(.system(size: NotchStyle.captionFontSize + 1, weight: .medium))
                .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                .lineLimit(1)
        }
        .frame(height: Self.headerHeight, alignment: .leading)
    }

    @ViewBuilder
    private var text: some View {
        if let meeting = preview?.meeting {
            invitation(meeting)
        } else {
            letterText
        }
    }

    /// Приглашение: когда и где, шкала с пересечениями, строка итога
    /// и текст приглашения под ними.
    private func invitation(_ meeting: ExternalNotice.LetterPreview.Meeting) -> some View {
        let clashes = meeting.clashes
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .foregroundStyle(Palette.calendar)
                Text(InvitationTimeline.span(meeting))
                    .foregroundStyle(.white.opacity(NotchStyle.primaryOpacity))
                if !meeting.location.isEmpty {
                    Text("· " + meeting.location)
                        .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                }
            }
            .font(.system(size: NotchStyle.captionFontSize + 1, weight: .medium))
            .lineLimit(1)
            if !meeting.isAllDay {
                InvitationTimeline(meeting: meeting)
                    .frame(height: InvitationTimeline.height)
            }
            HStack(spacing: 5) {
                Image(systemName: clashes.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                Text(clashes.isEmpty
                     ? t("Время свободно")
                     : tf("Пересекается: %@", clashes.map(InvitationTimeline.label).joined(separator: ", ")))
                    .lineLimit(1)
            }
            .font(.system(size: NotchStyle.captionFontSize, weight: .semibold))
            .foregroundStyle(clashes.isEmpty ? Palette.positive : Palette.negative)
            if let text = preview?.text, !text.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(text)
                        .font(.system(size: NotchStyle.captionFontSize))
                        .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Self.textHeight)
        .background(
            RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
                .fill(.white.opacity(NotchStyle.tileFill))
        )
    }

    private var letterText: some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(body_)
                .font(.system(size: NotchStyle.captionFontSize + 1))
                .foregroundStyle(.white.opacity(NotchStyle.primaryOpacity))
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(10)
        }
        .frame(height: Self.textHeight)
        .background(
            RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
                .fill(.white.opacity(NotchStyle.tileFill))
        )
    }

    /// Быстрые действия превью — «Ответить всем», «В архив», «Переслать»,
    /// «Напомнить через час»: поровну по ширине, значок и подпись.
    private var quickActions: some View {
        HStack(spacing: 6) {
            if let notice, let actions = notice.preview?.actions, !actions.isEmpty {
                ForEach(actions, id: \.id) { action in
                    Button(action: { onAction(notice, action) }) {
                        HStack(spacing: 4) {
                            Image(systemName: action.symbol)
                                .font(.system(size: NotchStyle.font(9.5), weight: .semibold))
                            Text(action.title)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                            .font(.system(size: NotchStyle.font(10.5), weight: .medium))
                            // «Принять» — зелёным, как согласие в плашках.
                            .foregroundStyle(action.isPositive ? Palette.positive : .white.opacity(NotchStyle.primaryOpacity))
                            .padding(.horizontal, 6)
                            .frame(maxWidth: .infinity)
                            .frame(height: Self.quickHeight)
                            .background(Capsule().fill(action.isPositive ? Palette.positive.opacity(0.18) : .white.opacity(0.12)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .notchHint(action.title)
                }
            }
        }
        .frame(height: Self.quickHeight)
    }

    /// Кнопки плашки, кроме самого превью. Нет их (чужая плашка без
    /// второй кнопки) — остаётся «Закрыть» в крыле.
    private var buttons: some View {
        HStack(spacing: NotchStyle.gridSpacing) {
            if let notice {
                ForEach(notice.actions.filter { !notice.isLocal($0) }, id: \.id) { action in
                    button(notice, action)
                }
            }
        }
        .frame(height: Self.buttonHeight)
    }

    private func button(_ notice: ExternalNotice, _ action: ExternalNotice.Action) -> some View {
        let shape = RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
        let tint = action.isPositive ? Palette.blue : Color.white
        return Button(action: { onAction(notice, action) }) {
            Label(action.title, systemImage: action.symbol)
                .font(.system(size: NotchStyle.rowFontSize, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: Self.buttonHeight)
                .background(shape.fill(tint.opacity(0.16)))
                .overlay(shape.strokeBorder(tint.opacity(0.5), lineWidth: 1))
                .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
    }
}

/// Шкала времени приглашения: час до и час после, приглашение верхней
/// полосой, встречи дня под ним — пересекающиеся красным. По ней видно,
/// не «пересекается ли», а насколько и с чем.
struct InvitationTimeline: View {
    let meeting: ExternalNotice.LetterPreview.Meeting

    static var height: CGFloat { NotchStyle.scaled(50) }
    private static let laneHeight: CGFloat = 10
    private static let lanes = 2

    /// Окно шкалы: от целого часа за час до начала до целого часа
    /// через час после конца.
    static func window(_ meeting: ExternalNotice.LetterPreview.Meeting, calendar: Calendar = .current) -> ClosedRange<Date> {
        func floorHour(_ date: Date) -> Date {
            calendar.dateInterval(of: .hour, for: date)?.start ?? date
        }
        let from = floorHour(meeting.start.addingTimeInterval(-3600))
        var to = floorHour(meeting.end.addingTimeInterval(3600))
        if to < meeting.end.addingTimeInterval(3600) { to = to.addingTimeInterval(3600) }
        return from...to
    }

    /// Встречи по дорожкам: накладывающиеся друг на друга — в разные.
    static func lanes(_ events: [ExternalNotice.LetterPreview.Meeting.Busy]) -> [[ExternalNotice.LetterPreview.Meeting.Busy]] {
        var lanes: [[ExternalNotice.LetterPreview.Meeting.Busy]] = []
        for event in events.sorted(by: { $0.start < $1.start }) {
            if let index = lanes.firstIndex(where: { ($0.last?.end ?? .distantPast) <= event.start }) {
                lanes[index].append(event)
            } else {
                lanes.append([event])
            }
        }
        return lanes
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Settings.shared.language.locale
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    /// «Планёрка 15:30–16:00».
    static func label(_ busy: ExternalNotice.LetterPreview.Meeting.Busy) -> String {
        "\(busy.title) \(time(busy.start))–\(time(busy.end))"
    }

    /// «Чт, 9 окт., 15:00–16:00» или «Чт, 9 окт., весь день».
    static func span(_ meeting: ExternalNotice.LetterPreview.Meeting) -> String {
        let day = DateFormatter()
        day.locale = Settings.shared.language.locale
        day.setLocalizedDateFormatFromTemplate("EEEdMMM")
        let date = day.string(from: meeting.start)
        guard !meeting.isAllDay else { return date + ", " + t("весь день") }
        return "\(date), \(time(meeting.start))–\(time(meeting.end))"
    }

    /// Полоса с названием внутри — если ширина позволяет.
    private func bar(_ title: String, width: CGFloat, height: CGFloat, fill: Color) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fill)
            .frame(width: width, height: height)
            .overlay(alignment: .leading) {
                if width > 34 {
                    Text(title)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                        .frame(width: width, alignment: .leading)
                }
            }
    }

    var body: some View {
        GeometryReader { proxy in
            let window = Self.window(meeting)
            let span = window.upperBound.timeIntervalSince(window.lowerBound)
            let width = proxy.size.width
            let x: (Date) -> CGFloat = { date in
                CGFloat(min(max(date.timeIntervalSince(window.lowerBound) / span, 0), 1)) * width
            }
            let hours = Int((span / 3600).rounded())
            ZStack(alignment: .topLeading) {
                // Часы: черта и подпись над каждым целым часом.
                ForEach(0...hours, id: \.self) { hour in
                    let date = window.lowerBound.addingTimeInterval(TimeInterval(hour) * 3600)
                    let left = x(date)
                    Rectangle()
                        .fill(.white.opacity(0.12))
                        .frame(width: 1, height: proxy.size.height - 12)
                        .offset(x: left, y: 12)
                    Text(Self.time(date))
                        .font(.system(size: 8.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                        .fixedSize()
                        .offset(x: min(max(left - 12, 0), width - 26))
                }
                // Приглашение — синим: красный занят пересечениями.
                bar(t("Приглашение"), width: max(3, x(meeting.end) - x(meeting.start)),
                    height: Self.laneHeight + 3, fill: Palette.blue.opacity(0.9))
                    .offset(x: x(meeting.start), y: 15)
                // Встречи дня по дорожкам.
                // Только те, что заходят в окно больше чем на пять минут:
                // огрызок в точку у края шкалы читался бы мусором.
                let visible = meeting.events.filter {
                    min($0.end, window.upperBound).timeIntervalSince(max($0.start, window.lowerBound)) > 300
                }
                ForEach(Array(Self.lanes(visible).prefix(Self.lanes).enumerated()), id: \.offset) { lane, events in
                    ForEach(Array(events.enumerated()), id: \.offset) { _, busy in
                        let clash = busy.start < meeting.end && busy.end > meeting.start
                        bar(busy.title, width: max(3, x(busy.end) - x(busy.start)), height: Self.laneHeight + 1,
                            fill: clash ? Palette.negative.opacity(0.85) : .white.opacity(0.25))
                            .offset(x: x(busy.start), y: 15 + Self.laneHeight + 6 + CGFloat(lane) * (Self.laneHeight + 4))
                            .help(Self.label(busy))
                    }
                }
            }
        }
    }
}

