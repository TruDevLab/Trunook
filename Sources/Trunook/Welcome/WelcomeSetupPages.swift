import SwiftUI

/// Шаги базовой настройки в окне знакомства.
///
/// Задача — чтобы после знакомства в настройки идти было незачем, и при этом
/// не завалить новичка: сперва он отмечает, чем пользуется, и дальше видит
/// только шаги для отмеченного (`WelcomeFlow.steps`). Каждый шаг — два-три
/// простых выбора; тонкости вроде Obsidian, провайдеров и команд остаются
/// в настройках.
extension WelcomeView {

    // MARK: - Чем пользуетесь

    var usesStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitle(t("Чем вы будете пользоваться?"),
                      subtitle: t("Отметьте нужное — дальше настроим только это. Остальное включается в настройках."))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(WelcomeFlow.Use.allCases) { use in
                    useTile(use)
                }
            }
        }
    }

    func useTile(_ use: WelcomeFlow.Use) -> some View {
        let on = use.isOn(in: settings)
        return Button {
            use.set(!on, in: settings)
            Haptics.tap()
        } label: {
            WelcomeCard(highlighted: on) {
                HStack(spacing: 11) {
                    WelcomeGlyph(symbol: use.symbol, tint: on ? use.tint : Color.white.opacity(0.4),
                                 size: WelcomeStyle.tile)
                    VStack(alignment: .leading, spacing: 2) {
                        // В две строки, а не с многоточием: «Календарь
                        // и вст…» в плитке выбора не говорит, что выбираешь.
                        Text(use.title)
                            .font(.system(size: WelcomeStyle.body, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(on ? 1 : 0.6))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(use.summary)
                            .font(.system(size: WelcomeStyle.caption, design: .rounded))
                            .foregroundStyle(Color.white.opacity(on ? 0.55 : 0.35))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: WelcomeStyle.title))
                        .foregroundStyle(on ? WelcomePalette.mint : Color.white.opacity(0.25))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, minHeight: WelcomeStyle.scaled(64), alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(use.title)
        .accessibilityValue(on ? t("Выбрано") : "")
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    // MARK: - Вид выреза

    var lookStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            stepTitle(t("Как будет выглядеть вырез"),
                      subtitle: t("Выбирая, смотрите на сам вырез — он раскроется."))
            HStack(spacing: 10) {
                ForEach(Surface.LookScale.steps, id: \.self) { level in
                    lookOption(level)
                }
            }
            WelcomeCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 13) {
                        WelcomeGlyph(symbol: "rectangle.on.rectangle", size: WelcomeStyle.tile)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t("На каких экранах"))
                                .font(.system(size: WelcomeStyle.title, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                            Text(settings.notchScreenMode.hint)
                                .font(.system(size: WelcomeStyle.detail, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.55))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Picker(t("На каких экранах"), selection: Binding(
                            get: { settings.notchScreenMode },
                            set: { settings.notchScreenMode = $0 }
                        )) {
                            ForEach(NotchScreenMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                    Divider().overlay(Color.white.opacity(0.08))
                    toggleRow(symbol: "cat", tint: WelcomePalette.violet,
                              title: t("Кот в чёлке"),
                              detail: t("Изредка выходит, пока вырезу нечего показывать"),
                              isOn: settings.binding(\.critterEnabled))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
        }
    }

    func lookOption(_ level: Int) -> some View {
        let selected = settings.notchLook == level
        return Button {
            settings.notchLook = level
            onPreviewNotch(4)
        } label: {
            VStack(spacing: 7) {
                LookSwatch(level: level)
                    .frame(height: WelcomeStyle.scaled(74))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(selected ? WelcomePalette.cyan : Color.white.opacity(0.1),
                                          lineWidth: selected ? 2 : 0.5)
                    )
                Text(Surface.LookScale.title(for: level))
                    .font(.system(size: WelcomeStyle.caption, weight: selected ? .semibold : .regular,
                                  design: .rounded))
                    .foregroundStyle(Color.white.opacity(selected ? 1 : 0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(Surface.LookScale.title(for: level))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Календарь

    var calendarStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepTitle(t("Календарь и встречи"),
                      subtitle: t("Какие календари показывать и когда напоминать о встрече."))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    if calendar.eventsAccess != .fullAccess {
                        permissionRow(.calendar)
                    } else if !calendar.availableCalendars.isEmpty {
                        calendarsCard
                    }
                    WelcomeCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 13) {
                                WelcomeGlyph(symbol: "bell.badge", size: WelcomeStyle.tile)
                                Text(t("Напоминать о встрече"))
                                    .font(.system(size: WelcomeStyle.title, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                Spacer(minLength: 8)
                                Picker(t("Напоминать о встрече"), selection: settings.binding(\.eventLeadMinutes)) {
                                    Text(t("в начале")).tag(0)
                                    Text(t("за 5 мин")).tag(5)
                                    Text(t("за 10 мин")).tag(10)
                                    Text(t("за 15 мин")).tag(15)
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .fixedSize()
                            }
                            Divider().overlay(Color.white.opacity(0.08))
                            toggleRow(symbol: "video.fill", tint: WelcomePalette.violet,
                                      title: t("Кнопки звонка в вырезе"),
                                      detail: t("Микрофон, камера и выход, пока идёт встреча в браузере, Zoom или Телемосте"),
                                      isOn: settings.binding(\.meetingControlsEnabled))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                    }
                }
            }
        }
    }

    var calendarsCard: some View {
        let sources = calendar.availableCalendars
        let all = sources.map(\.id)
        return WelcomeCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 13) {
                    WelcomeGlyph(symbol: "calendar.badge.checkmark", size: WelcomeStyle.tile)
                    Text(t("Какие календари показывать"))
                        .font(.system(size: WelcomeStyle.title, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                // Два столбца: календарей у рабочего человека бывает десяток,
                // и списком в один столбец карточка уходила бы за окно.
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
                    ForEach(sources) { source in
                        Toggle(isOn: Binding(
                            get: { settings.isSourceEnabled(source.id, in: \.enabledCalendarIDs, all: all) },
                            set: { settings.setSource(source.id, enabled: $0, in: \.enabledCalendarIDs, all: all) }
                        )) {
                            HStack(spacing: 6) {
                                Circle().fill(source.color).frame(width: 8, height: 8)
                                Text(source.title)
                                    .font(.system(size: WelcomeStyle.detail, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.8))
                                    .lineLimit(1)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }

    // MARK: - Погода и перерывы

    var weatherStep: some View {
        let uses = WelcomeFlow.uses(in: settings)
        return VStack(alignment: .leading, spacing: 12) {
            stepTitle(uses.contains(.weather) && uses.contains(.breaks)
                      ? t("Погода и перерывы")
                      : (uses.contains(.weather) ? t("Погода") : t("Перерывы")),
                      subtitle: t("Где смотреть погоду и как часто напоминать встать из-за стола."))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    if uses.contains(.weather) { weatherRow }
                    if uses.contains(.breaks) { breaksCard }
                }
            }
        }
    }

    var breaksCard: some View {
        WelcomeCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 13) {
                    WelcomeGlyph(symbol: "figure.cooldown", tint: WelcomePalette.mint, size: WelcomeStyle.tile)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Перерывы"))
                            .font(.system(size: WelcomeStyle.title, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(t("Считается только время за компьютером"))
                            .font(.system(size: WelcomeStyle.detail, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                }
                ForEach(BreakKind.allCases) { kind in
                    HStack {
                        Text(kind.title)
                            .font(.system(size: WelcomeStyle.body, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.85))
                        Spacer(minLength: 8)
                        Picker(kind.title, selection: Binding(
                            get: { kind.minutes(in: settings) },
                            set: { kind.setMinutes($0, in: settings) }
                        )) {
                            Text(t("Не напоминать")).tag(0)
                            ForEach(BreakKind.choices, id: \.self) { minutes in
                                Text(tf("Каждые %d мин", minutes)).tag(minutes)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
    }

    // MARK: - Главный экран

    var homeStep: some View {
        let suggested = WelcomeFlow.home(for: WelcomeFlow.uses(in: settings))
        let applied = settings.homeWidgets.map(\.kind) == suggested.map(\.kind)
            && settings.homeWidgets.map(\.size) == suggested.map(\.size)
        return VStack(alignment: .leading, spacing: 14) {
            stepTitle(t("Главный экран"),
                      subtitle: t("Раскрытый вырез — сетка плиток. Соберём её из того, чем вы пользуетесь."))
            WelcomeCard {
                WelcomeHomePreview(widgets: suggested)
                    .padding(14)
            }
            HStack(spacing: 10) {
                Button {
                    settings.homeWidgets = suggested
                    onPreviewNotch(5)
                } label: {
                    Label(applied ? t("Собрано") : t("Собрать так"),
                          systemImage: applied ? "checkmark" : "square.grid.2x2")
                }
                .buttonStyle(WelcomeGhostButton())
                .disabled(applied)
                Text(t("Плитки можно переставить в настройках, раздел «Главный экран»."))
                    .font(.system(size: WelcomeStyle.caption, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        }
    }

    // MARK: - Управление: жесты и сочетания

    /// Жесты и сочетания — одним шагом, и сочетания только для выбранного:
    /// клавиша телесуфлера тому, кто его не открывал, — лишняя строка.
    var controlsStep: some View {
        let uses = WelcomeFlow.uses(in: settings)
        return VStack(alignment: .leading, spacing: 12) {
            stepTitle(t("Как этим пользоваться"),
                      subtitle: t("Вырез не отбирает фокус. Сочетания — на ⌃⌥, любое можно сменить прямо здесь."))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel(t("Жесты"))
                    gesture("cursorarrow.rays", t("Наведите курсор на вырез"),
                            t("Мини-вид: что играет и когда ближайшая встреча"))
                    gesture("hand.tap.fill", t("Нажмите или потяните вниз"),
                            t("Главный экран целиком. Свайп вверх сворачивает его"))
                    gesture("circle.grid.3x3.fill", t("Задержите нажатие на чёлке"),
                            t("Веером выедут кружки всех функций — ведите руку к нужному"))
                    if uses.contains(.music) {
                        gesture("arrow.left.arrow.right", t("Свайп двумя пальцами"),
                                t("Предыдущий и следующий трек"))
                    }
                    sectionLabel(t("Сочетания клавиш"))
                    if uses.contains(.assistant) { assistantHotKeyRow }
                    if uses.contains(.clipboard) { clipboardHotKeyRow }
                    if uses.contains(.calendar) { calendarHotKeyRow }
                    if uses.contains(.notes) { notesHotKeyRow; recordHotKeyRow }
                    if uses.contains(.timer) { timerHotKeyRow }
                    if uses.contains(.shelf) { shelfHotKeyRow }
                    if uses.contains(.assistant) { voiceTriggerRow }
                }
            }
        }
    }

    func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: WelcomeStyle.micro, weight: .semibold, design: .monospaced))
            .tracking(1.6)
            .foregroundStyle(Color.white.opacity(0.4))
            .padding(.top, 6)
            .padding(.leading, 4)
    }

    // MARK: - Общее

    func toggleRow(symbol: String, tint: Color, title: String, detail: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 13) {
            WelcomeGlyph(symbol: symbol, tint: tint, size: WelcomeStyle.tile)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: WelcomeStyle.title, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: WelcomeStyle.detail, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            // Подпись скрыта визуально — слева своя строка, — но остаётся
            // для диктора: без неё выключатель объявлялся безымянным.
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(WelcomePalette.cyan)
        }
    }
}

/// Образец вида выреза: пёстрые обои и на них панель так, как она будет
/// выглядеть. Настоящее стекло в окне знакомства не нарисовать — потому
/// выбор и раскрывает сам вырез, а образец лишь подсказывает направление.
struct LookSwatch: View {
    let level: Int

    private var wallpaper: some View {
        LinearGradient(colors: [WelcomePalette.violet, WelcomePalette.rose, WelcomePalette.amber, WelcomePalette.cyan],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(
                // Полосы — чтобы было видно, размыто за панелью или нет.
                HStack(spacing: 6) {
                    ForEach(0..<8, id: \.self) { _ in
                        Rectangle().fill(Color.white.opacity(0.35)).frame(width: 3)
                    }
                }
            )
    }

    var body: some View {
        GeometryReader { proxy in
            let panel = RoundedRectangle(cornerRadius: 10, style: .continuous)
            let width = proxy.size.width * 0.76
            let height = proxy.size.height * 0.7
            ZStack(alignment: .top) {
                wallpaper
                ZStack {
                    switch Surface.LookScale.snap(level) {
                    case Surface.LookScale.glass:
                        panel.fill(Color.white.opacity(0.04))
                        panel.strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
                    case Surface.LookScale.hazy:
                        panel.fill(Color.black.opacity(0.35))
                        panel.strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                    case Surface.LookScale.matte:
                        wallpaper.blur(radius: 6).clipShape(panel)
                        panel.fill(Color.black.opacity(0.35))
                    case Surface.LookScale.dark:
                        wallpaper.blur(radius: 6).clipShape(panel)
                        panel.fill(Color.black.opacity(0.62))
                    default:
                        panel.fill(Color.black)
                    }
                    // Две «плитки» на панели — видно, чем они отделяются.
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.35))
                        RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.35))
                    }
                    .padding(8)
                    .padding(.top, 8)
                }
                .frame(width: width, height: height)
                // Чёрная полоса чёлки сверху — как у настоящего выреза.
                Capsule().fill(Color.black).frame(width: width * 0.4, height: 8).offset(y: -4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// Сетка будущего главного экрана: плитки на своих местах, со значком
/// и названием — чтобы было видно, что соберётся, до того как собрать.
struct WelcomeHomePreview: View {
    let widgets: [HomeWidget]

    private static var cellHeight: CGFloat { WelcomeStyle.scaled(46) }
    private static let gap: CGFloat = 6

    var body: some View {
        let grid = HomeGrid.place(widgets)
        let rows = max(1, grid.rows)
        GeometryReader { proxy in
            let gap = Self.gap
            let columns = CGFloat(HomeGrid.columns)
            let cellWidth = (proxy.size.width - gap * (columns - 1)) / columns
            ZStack(alignment: .topLeading) {
                ForEach(grid.placements) { placement in
                    let size = placement.widget.size
                    let width = cellWidth * CGFloat(size.columns) + gap * CGFloat(size.columns - 1)
                    let height = Self.cellHeight * CGFloat(size.rows) + gap * CGFloat(size.rows - 1)
                    tile(placement.widget.kind)
                        .frame(width: width, height: height)
                        .offset(x: CGFloat(placement.column) * (cellWidth + gap),
                                y: CGFloat(placement.row) * (Self.cellHeight + gap))
                }
            }
        }
        .frame(height: Self.cellHeight * CGFloat(rows) + Self.gap * CGFloat(rows - 1))
    }

    private func tile(_ kind: HomeWidgetKind) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.white.opacity(0.07))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    Image(systemName: kind.symbol)
                        .font(.system(size: WelcomeStyle.caption, weight: .semibold))
                        .foregroundStyle(kind.tint)
                    Text(kind.title)
                        .font(.system(size: WelcomeStyle.caption, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .lineLimit(1)
                }
                .padding(8)
            }
    }
}
