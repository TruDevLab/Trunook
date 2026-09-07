import SwiftUI

/// Окно правки события.
///
/// Открывается двумя путями: нажатием по событию в мини-календаре и нажатием
/// по строке события на главном экране. Раньше второй путь вёл в Календарь
/// Apple — то есть уводил из выреза в чужое окно поверх работы ради того,
/// чтобы поменять час или прочитать, где встреча.
///
/// **Время правится кнопками, а не набором.** Разбирать «12.09.2026» из строки
/// — работа, ломающаяся на каждой второй раскладке и на каждом чужом порядке
/// дня и месяца; шаг стрелкой не ломается никогда. Шаг в четверть часа:
/// встречи назначают на круглые четверти.
///
/// **Подробности только читаются.** Многострочное поле заняло бы всю панель,
/// а приглашение с повесткой правят там, где его составляли. Человеку здесь
/// нужно другое — увидеть, о чём встреча, и попасть по ссылке.
struct EventEditorPanel: View {
    let draft: EventDraft
    let metrics: NotchMetrics
    /// Есть ли куда возвращаться. Правку открывают из двух мест, и с главного
    /// экрана возвращаться некуда — там кнопка обещала бы месяц, в который
    /// человек не заходил.
    let canReturn: Bool
    /// Календари, в которые можно писать, — из них и выбирают.
    let calendars: [CalendarSource]
    let onChooseCalendar: (String) -> Void
    let onCycleCalendar: () -> Void
    let onChangeTitle: (String) -> Void
    let onChangeLocation: (String) -> Void
    let onChangeNotes: (String) -> Void
    let onChooseSeries: (Bool) -> Void
    let onBack: () -> Void
    let onMoveDay: (Int) -> Void
    let onMoveStart: (Int) -> Void
    let onStretch: (Int) -> Void
    let onToggleAllDay: () -> Void
    let onOpenLink: (URL) -> Void
    let onSave: () -> Void
    let onDelete: () -> Void
    let onClose: () -> Void

    // MARK: - Размеры

    static var width: CGFloat { NotchStyle.scaled(500) }
    static let bodyPadding: CGFloat = NotchStyle.bottomPadding

    private static var fieldHeight: CGFloat { NotchStyle.scaled(28) }
    private static var stepperHeight: CGFloat { NotchStyle.scaled(26) }
    /// Поле описания. Выше прежних шестидесяти: под ссылкой встречи там
    /// оставалось две строки текста, и приглашение приходилось читать
    /// в щёлку.
    private static var notesHeight: CGFloat { NotchStyle.scaled(84) }
    private static var attendeesHeight: CGFloat { NotchStyle.scaled(24) }
    private static var actionsHeight: CGFloat { NotchStyle.rowHeight }

    /// Высота одна на все события — и на встречу с повесткой, и на голую
    /// пометку в календаре.
    ///
    /// Панель, которая меряется по содержимому, растит `ZStack`, а `frame`
    /// центрирует переросшее — и панель вылезает вверх поверх соседей.
    /// В проекте на этом ловились дважды, поэтому размер задаётся снаружи,
    /// а лишнее обрезается прокруткой подробностей.
    static var contentHeight: CGFloat {
        fieldHeight + stepperHeight + fieldHeight + notesHeight + attendeesHeight
            + actionsHeight + NotchStyle.gridSpacing * 5
    }

    static func height(notchHeight: CGFloat) -> CGFloat {
        NotchStyle.height(notchHeight: notchHeight, contentHeight: contentHeight)
    }

    // MARK: - Тело

    var body: some View {
        NotchPanel(metrics: metrics, width: Self.width, bodyPadding: Self.bodyPadding) {
            // Заголовок и есть предупреждение: повторяющееся событие названо
            // повторяющимся в самом заметном месте панели, до того как человек
            // тронул хоть одно поле. Значок при этом меняется на кольцо
            // повтора — по нему видно даже не читая.
            NotchPanelTitle(
                symbol: draft.isRecurring ? "repeat" : "calendar",
                title: heading,
                tint: tint
            )
        } trailing: {
            HStack(spacing: 2) {
                // Возврат в календарь — своей кнопкой, а не крестиком.
                // Крестик закрывает вырез целиком, и человек, пришедший
                // в правку из месяца, терял вместе с ней и месяц: чтобы
                // взглянуть на соседнюю встречу, надо было открывать
                // календарь заново.
                //
                // Кнопка живёт значением, а не веткой: с главного экрана
                // возвращаться некуда, и она там просто не занимает места.
                if canReturn {
                    NotchPanelButton(
                        symbol: "chevron.left",
                        hint: t("Назад к календарю"),
                        action: onBack
                    )
                }
                NotchPanelButton(symbol: "xmark", hint: t("Закрыть"), action: onClose)
            }
        } content: {
            VStack(spacing: NotchStyle.gridSpacing) {
                titleField
                // Сразу под названием: «куда положить» и «с кем» — это про
                // само событие, а не про его подробности. Внизу, под
                // описанием, календарь читался ещё одним полем приглашения
                // и попадался на глаза последним — то есть уже после того,
                // как человек нажал «Сохранить».
                attendees
                timeRow
                locationField
                notesField
                actions
            }
            .frame(height: Self.contentHeight)
        }
    }

    private var heading: String {
        if draft.isNew { return t("Новое событие") }
        return draft.isRecurring ? t("Повторяется") : t("Событие")
    }

    /// Календарь, в который событие ляжет.
    private var chosen: CalendarSource? {
        calendars.first { $0.id == draft.calendarID }
    }

    /// Цвет календаря, в котором событие живёт.
    ///
    /// Сперва выбранного — он меняется прямо здесь, и панель обязана
    /// перекраситься следом, иначе выбор выглядит несработавшим. Если
    /// выбранного в списке нет (календарь только для чтения — такое бывает
    /// у чужих приглашений), берётся цвет самого события, а у нового —
    /// общий цвет календаря.
    private var tint: Color {
        if let chosen { return chosen.color }
        guard let components = draft.colorComponents, components.count >= 3 else {
            return Palette.calendar
        }
        return Color(
            red: Double(components[0]),
            green: Double(components[1]),
            blue: Double(components[2])
        )
    }

    // MARK: - Поля

    /// Фокус достаётся названию, а не месту.
    ///
    /// Полей два, и оба забирали его наперегонки: побеждало построенное
    /// последним, то есть «Место», — а печатать человек начинает с названия,
    /// особенно в только что заведённом событии, где названия ещё нет вовсе.
    private var titleField: some View {
        field(
            symbol: "textformat",
            text: draft.title,
            placeholder: t("Название события"),
            focused: true,
            onChange: onChangeTitle,
            onSubmit: onSave
        )
        .frame(height: Self.fieldHeight)
    }

    private var locationField: some View {
        field(
            symbol: "mappin.and.ellipse",
            text: draft.location,
            placeholder: t("Место"),
            focused: false,
            onChange: onChangeLocation,
            onSubmit: onSave
        )
        .frame(height: Self.fieldHeight)
    }

    private func field(
        symbol: String,
        text: String,
        placeholder: String,
        focused: Bool,
        onChange: @escaping (String) -> Void,
        onSubmit: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: NotchStyle.font(10), weight: .semibold))
                .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                .frame(width: 14)
                .accessibilityHidden(true)
            FocusedTextField(
                text: Binding(get: { text }, set: onChange),
                placeholder: placeholder,
                onSubmit: onSubmit,
                focusesOnAppear: focused
            )
            .accessibilityLabel(placeholder)
        }
        .padding(.horizontal, 10)
        .surface(.card, in: Capsule(), glass: Surface.inNotch)
    }

    // MARK: - Время

    private var timeRow: some View {
        HStack(spacing: 6) {
            stepper(
                value: Self.dayLabel(draft.start),
                hint: t("День"),
                back: { onMoveDay(-1) },
                forward: { onMoveDay(1) }
            )
            stepper(
                value: draft.isAllDay ? t("весь день") : Self.timeLabel(draft.start),
                hint: t("Начало"),
                back: { onMoveStart(-1) },
                forward: { onMoveStart(1) },
                isEnabled: !draft.isAllDay
            )
            stepper(
                value: draft.isAllDay ? "—" : draft.durationLabel,
                hint: t("Длительность"),
                back: { onStretch(-1) },
                forward: { onStretch(1) },
                isEnabled: !draft.isAllDay
            )
            allDayToggle
        }
        .frame(height: Self.stepperHeight)
    }

    /// Значение между двумя стрелками.
    ///
    /// Стрелки по бокам, а не обе справа: так пара читается как «меньше —
    /// больше» вокруг того, что меняется, и не требует целиться в две
    /// соседние кнопки размером с половину строки.
    private func stepper(
        value: String,
        hint: String,
        back: @escaping () -> Void,
        forward: @escaping () -> Void,
        isEnabled: Bool = true
    ) -> some View {
        HStack(spacing: 0) {
            stepperArrow("chevron.left", run: back)
            Text(value)
                .font(.system(size: NotchStyle.captionFontSize, weight: .medium))
                .foregroundStyle(.white.opacity(isEnabled ? NotchStyle.primaryOpacity : 0.35))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
            stepperArrow("chevron.right", run: forward)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.stepperHeight)
        .surface(
            .card,
            in: RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous),
            glass: Surface.inNotch
        )
        .opacity(isEnabled ? 1 : 0.5)
        .disabled(!isEnabled)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(hint)
        .accessibilityValue(value)
    }

    private func stepperArrow(_ symbol: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Image(systemName: symbol)
                .font(.system(size: NotchStyle.font(9), weight: .semibold))
                .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                .frame(width: Self.stepperHeight, height: Self.stepperHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    private var allDayToggle: some View {
        Button(action: onToggleAllDay) {
            Image(systemName: draft.isAllDay ? "sun.max.fill" : "clock")
                .font(.system(size: NotchStyle.font(11), weight: .semibold))
                .foregroundStyle(draft.isAllDay ? tint : .white.opacity(NotchStyle.secondaryOpacity))
                .frame(width: Self.stepperHeight + 8, height: Self.stepperHeight)
                .surface(
                    .segment,
                    in: RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous),
                    tint: tint,
                    lit: draft.isAllDay,
                    glass: Surface.inNotch && draft.isAllDay
                )
                .contentShape(RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .notchHint(t("Весь день"))
        .accessibilityAddTraits(draft.isAllDay ? [.isSelected] : [])
    }

    // MARK: - Описание

    /// Описание правится, а не только читается: чаще всего в него дописывают
    /// строку — ссылку, номер комнаты, что принести, — и уходить ради одной
    /// строки в Календарь значило бы оставить в вырезе половину дела.
    ///
    /// Ссылка встречи стоит **над** текстом, а не в нём: за ней приходят
    /// чаще, чем за повесткой, и искать её в трёх абзацах пришлось бы
    /// каждый раз заново.
    private var notesField: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.alignleft")
                .font(.system(size: NotchStyle.font(10), weight: .semibold))
                .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                .frame(width: 14)
                .padding(.top, 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                if let link = draft.link {
                    joinButton(link)
                }
                PlainTextEditor(
                    text: Binding(get: { draft.notes }, set: onChangeNotes),
                    placeholder: t("Описание")
                )
                .accessibilityLabel(t("Описание"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(height: Self.notesHeight)
        // Обрезка обязательна: `NSTextView` растёт по своему тексту и о раме
        // SwiftUI не знает вовсе, а рама сама по себе ничего не обрезает.
        // Прокрутка внутри поля это уже чинит, но подстраховка здесь дешевле
        // второго такого снимка — приглашения, накрывшего кнопки панели.
        .clipped()
        .surface(
            .card,
            in: RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous),
            glass: Surface.inNotch
        )
    }

    private func joinButton(_ link: MeetingLink) -> some View {
        Button(action: { onOpenLink(link.url) }) {
            Label(link.provider.title, systemImage: link.provider.symbol)
                .font(.system(size: NotchStyle.captionFontSize, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: NotchStyle.scaled(20))
                .accentSurface(in: Capsule(), tint: tint, glass: Surface.inNotch)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .fixedSize()
        .notchActionHint(t("Открыть ссылку встречи"))
    }

    // MARK: - Участники

    /// Куда ляжет событие.
    ///
    /// До этого выбора не было вовсе: новое событие молча уходило в системный
    /// календарь по умолчанию, а если тот был снят в списке показываемых —
    /// в первый попавшийся из доступных на запись. Узнать об этом можно было,
    /// только открыв Календарь.
    ///
    /// **Нажатие перебирает по кругу**, правая кнопка открывает весь список.
    /// Так же устроено переключение динамиков в панели встречи, и по той же
    /// причине: список короткий, а выпадающему меню в вырезе негде лечь —
    /// система ставит его по центру экрана, то есть под чёлку, и панель
    /// его закрывает.
    private var calendarChip: some View {
        Button(action: onCycleCalendar) {
            HStack(spacing: 5) {
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                Text(chosen?.title ?? t("Календарь по умолчанию"))
                    .font(.system(size: NotchStyle.captionFontSize))
                    .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(height: NotchStyle.scaled(20))
            .surface(.card, in: Capsule(), glass: Surface.inNotch)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(calendars.count < 2)
        .contextMenu {
            ForEach(calendars) { source in
                Button(source.title) { onChooseCalendar(source.id) }
            }
        }
        .notchHint(t("Куда положить"))
        .accessibilityLabel(t("Куда положить"))
        .accessibilityValue(chosen?.title ?? "")
    }

    /// Приглашённые — одной строкой и только на чтение.
    ///
    /// Менять список нечем: `EventKit` не даёт стороннему приложению ни
    /// добавить участника, ни убрать — приглашения рассылает сервер
    /// календаря. Показывать при этом надо: «кто ещё придёт» — второй вопрос
    /// к встрече после «когда», и ради него уходили в Календарь.
    ///
    /// Ответ каждого — значком, а не словом: слов на строку не хватит уже
    /// при трёх участниках, а значок читается и в конце длинного ряда.
    private var attendees: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Календарь и участники делят одну строку: это два ответа
                // на один вопрос — где встреча числится и с кем она. Своей
                // строки ни одному из них не нужно, а панель от лишней
                // строки выросла бы на весь её рост.
                calendarChip
                Image(systemName: "person.2")
                    .font(.system(size: NotchStyle.font(10), weight: .semibold))
                    .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                    .frame(width: 14)
                    .accessibilityHidden(true)
                if draft.attendees.isEmpty {
                    Text(t("Участников нет"))
                        .font(.system(size: NotchStyle.captionFontSize))
                        .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                } else {
                    ForEach(draft.attendees) { person in
                        attendee(person)
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: Self.attendeesHeight)
    }

    private func attendee(_ person: EventDraft.Attendee) -> some View {
        HStack(spacing: 4) {
            Image(systemName: person.status.symbol)
                .font(.system(size: NotchStyle.font(9)))
                .foregroundStyle(Self.color(of: person.status))
            Text(person.isMe ? t("я") : person.name)
                .font(.system(size: NotchStyle.captionFontSize))
                .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .frame(height: NotchStyle.scaled(20))
        .surface(.card, in: Capsule(), glass: Surface.inNotch)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((person.isMe ? t("я") : person.name) + ", " + person.status.title)
    }

    /// Цвет ответа. Отказ — тем же оттенком, что и удаление: это единственная
    /// строка, из-за которой встречу может и не быть смысла проводить.
    private static func color(of status: EventDraft.Attendee.Status) -> Color {
        switch status {
        case .accepted: return Palette.notes
        case .declined: return Palette.timer
        case .tentative, .pending: return .white.opacity(NotchStyle.tertiaryOpacity)
        }
    }

    // MARK: - Кнопки

    private var actions: some View {
        HStack(spacing: 6) {
            // Удаление — слева и без подложки, подальше от «Сохранить»:
            // это единственное здесь действие, которого не отменить.
            Button(action: onDelete) {
                Label(t("Удалить"), systemImage: "trash")
                    .font(.system(size: NotchStyle.font(11), weight: .medium))
                    .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                    .padding(.horizontal, 10)
                    .frame(height: Self.actionsHeight)
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            .disabled(draft.isNew)
            .opacity(draft.isNew ? 0 : 1)

            Spacer(minLength: 0)

            // Выбор ряда стоит вплотную к «Сохранить», а не отдельной
            // строкой наверху: он объясняет, что именно сделает эта кнопка,
            // и читать его надо перед нажатием, а не десятью строками выше.
            // Строку он при этом не занимает — в ряду кнопок и без него
            // была пустота во всю ширину.
            if draft.isRecurring {
                seriesChoice
            }

            Button(action: onSave) {
                Label(t("Сохранить"), systemImage: "checkmark")
                    .font(.system(size: NotchStyle.font(11), weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: Self.actionsHeight)
                    .accentSurface(in: Capsule(), tint: tint, glass: Surface.inNotch)
                    .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            // Событие без названия в списке неотличимо от любого другого
            // безымянного, поэтому пустое имя не сохраняется.
            .disabled(!draft.isSavable)
            .opacity(draft.isSavable ? 1 : 0.45)
        }
        .frame(height: Self.actionsHeight)
    }

    /// Одно вхождение или весь ряд.
    ///
    /// «Только это» стоит первым и выбрано по умолчанию: разница здесь
    /// молчаливая и необратимая — перенеся одну встречу на час, человек
    /// не ждёт, что переедут все прошлые и будущие, а откатить это
    /// в Календаре потом нечем.
    private var seriesChoice: some View {
        HStack(spacing: 3) {
            seriesOption(t("Только это"), chosen: !draft.editsSeries) { onChooseSeries(false) }
            seriesOption(t("Весь ряд"), chosen: draft.editsSeries) { onChooseSeries(true) }
        }
        .padding(3)
        // Общая дорожка под обоими: то, что делает их одним выбором,
        // а не двумя действиями. Та же сборка, что у переключателя режимов
        // в таймере.
        .surface(.card, in: Capsule(), glass: Surface.inNotch)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(t("Что менять"))
    }

    private func seriesOption(
        _ title: String,
        chosen: Bool,
        run: @escaping () -> Void
    ) -> some View {
        Button(action: run) {
            Text(title)
                .font(.system(size: NotchStyle.font(10), weight: .medium))
                .foregroundStyle(.white.opacity(chosen ? 1 : NotchStyle.secondaryOpacity))
                .padding(.horizontal, 9)
                .frame(height: Self.actionsHeight - 6)
                .surface(.segment, in: Capsule(), lit: chosen, glass: Surface.inNotch && chosen)
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }

    // MARK: - Записи

    static func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Localization.shared.resolved.locale
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter.string(from: date)
    }

    static func timeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
