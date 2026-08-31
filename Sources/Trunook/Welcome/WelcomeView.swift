import AppKit
import SwiftUI

/// Окно знакомства: четыре шага — что это, как управлять, доступы, готово.
struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel
    @ObservedObject var calendar: CalendarService
    @ObservedObject var launchAtLogin: LaunchAtLogin
    /// Сочетание меню правится прямо здесь, поэтому настройки наблюдаются,
    /// а не берутся снимком.
    @ObservedObject var settings: Settings
    /// Погода — единственное, чему нужна геопозиция, и здесь же выбирается
    /// город, если отдавать её не хочется.
    @ObservedObject var weather: WeatherService
    /// Набранное и найденное при поиске города: `@State` в этом SDK
    /// недоступен, держать негде.
    @ObservedObject var placeSearch: WeatherPlaceSearch
    /// Сочетания заданы пользователем — после правки их надо
    /// перерегистрировать в системе.
    let onHotKeysChanged: () -> Void
    let onFinish: () -> Void

    static var size: CGSize { WelcomeStyle.windowSize }

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 0) {
                header
                Spacer(minLength: 12)
                content
                    .frame(maxWidth: .infinity)
                Spacer(minLength: 12)
                footer
            }
            .padding(.horizontal, 44)
            .padding(.top, 26)
            .padding(.bottom, 26)
        }
        // Размер задан окном, вёрстка растягивается под него: так фон
        // закрашивает всё до кромок, чем бы окно ни оказалось на деле.
        .frame(
            minWidth: Self.size.width,
            maxWidth: .infinity,
            minHeight: Self.size.height,
            maxHeight: .infinity
        )
        .preferredColorScheme(.dark)
    }

    // MARK: - Шапка

    private var header: some View {
        HStack(alignment: .center) {
            WelcomeEyebrow(text: model.step.eyebrow)
            Spacer(minLength: 0)
            languagePicker
            stepIndicator
        }
    }

    /// Язык переключается прямо здесь, а не только в настройках: человек,
    /// открывший приложение впервые, ещё не знает, где эти настройки, —
    /// а прочитать знакомство ему нужно уже сейчас.
    private var languagePicker: some View {
        Menu {
            ForEach(Language.allCases) { language in
                Button {
                    settings.language = language
                } label: {
                    if settings.language == language {
                        Label(language.title, systemImage: "checkmark")
                    } else {
                        Text(language.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "globe")
                    .font(.system(size: WelcomeStyle.micro, weight: .medium))
                Text(settings.language.title)
                    .font(.system(size: WelcomeStyle.caption, weight: .medium, design: .rounded))
            }
            .foregroundStyle(Color.white.opacity(0.7))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.07))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.13), lineWidth: 0.5))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.trailing, 14)
    }

    /// Полоски шагов заодно работают навигацией: вернуться к разрешениям
    /// с последнего шага иначе можно было бы только кнопкой «Назад».
    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(WelcomeModel.Step.allCases) { step in
                let isCurrent = step == model.step
                Button {
                    model.go(to: step)
                } label: {
                    Capsule()
                        .fill(isCurrent ? WelcomePalette.cyan
                                        : Color.white.opacity(0.16))
                        .frame(width: isCurrent ? 26 : 12, height: 4)
                        .contentShape(Capsule().inset(by: -6))
                }
                .buttonStyle(.plain)
                // Внутри кнопки одна `Capsule` — выводить имя SwiftUI не из
                // чего, и диктор произносил «кнопка» пять раз подряд. Имя
                // берётся из самого шага, а «этот сейчас открыт» уходит
                // в значение и признак: меняющееся имя диктор прочёл бы
                // как другую кнопку, а не как ту же в другом состоянии.
                .accessibilityLabel(step.title)
                .accessibilityValue(isCurrent ? t("Текущий шаг") : "")
                .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
                .animation(.easeOut(duration: 0.25), value: model.step)
            }
        }
    }

    // MARK: - Содержимое шага

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .intro: introStep
        case .gestures: gesturesStep
        case .shortcuts: shortcutsStep
        case .permissions: permissionsStep
        case .done: doneStep
        }
    }

    // MARK: Шаг 1 — что это

    private var introStep: some View {
        VStack(spacing: 22) {
            VStack(spacing: 9) {
                Text("Trunook")
                    .font(.system(size: WelcomeStyle.hero, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(t("Вырез MacBook становится центром управления"))
                    .font(.system(size: WelcomeStyle.deck, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.62))
            }
            WelcomeNotchDemo()
            featureRow
        }
    }

    /// Два ряда по семь.
    ///
    /// Длина ряда — не вкусовщина, а расчёт: содержимое, которое шире окна,
    /// раздвигает его, и обрезаются **оба** края разом — заголовок слева,
    /// кнопки справа. На восьми плитках по 96 точек это уже ловили.
    /// Семь по 88 с зазорами дают 676 точек при окне 780 — запас есть,
    /// и его держит проверка `рядыПлитокПомещаютсяВОкно`.
    /// Третий ряд не заводить: под ним ещё демонстрация выреза и заголовок.
    ///
    /// Заметки и голос стоят рядом с моделью намеренно: это одна и та же
    /// панель и один и тот же разговор — порознь они читались бы как три
    /// разные функции. Ради этого буфер уехал во второй ряд: соседство
    /// по смыслу важнее порядка, в котором функции появлялись.
    private var featureRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                feature("music.note", t("Музыка"), WelcomePalette.violet)
                feature("calendar", t("Календарь"), WelcomePalette.cyan)
                feature("text.viewfinder", t("Захват"), WelcomePalette.mint)
                feature("video.fill", t("Встречи"), WelcomePalette.violet)
                feature("sparkles", t("Модель"), WelcomePalette.violet)
                feature("waveform", t("Голос"), WelcomePalette.violet)
                feature("list.bullet.rectangle", t("Заметки"), WelcomePalette.violet)
            }
            HStack(spacing: 10) {
                feature("doc.on.clipboard.fill", t("Буфер"), WelcomePalette.cyan)
                feature("tray.full.fill", t("Полка"), WelcomePalette.violet)
                feature("timer", t("Таймер"), WelcomePalette.mint)
                feature("gauge.with.dots.needle.67percent", t("Нагрузка"), WelcomePalette.cyan)
                feature("text.alignleft", t("Суфлер"), WelcomePalette.violet)
                feature("cloud.sun.fill", t("Погода"), WelcomePalette.cyan)
                feature("bolt.fill", t("Питание"), WelcomePalette.mint)
            }
        }
    }

    /// Сколько плиток в самом длинном ряду — для проверки ширины.
    static let widestFeatureRow = 7

    private func feature(_ symbol: String, _ title: String, _ tint: Color) -> some View {
        WelcomeCard {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: WelcomeStyle.glyph, weight: .medium))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: WelcomeStyle.caption, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.72))
            }
            .frame(width: WelcomeStyle.featureTile.width,
                   height: WelcomeStyle.featureTile.height)
        }
    }

    // MARK: Шаг 2 — управление

    /// Шаг жестов и шаг сочетаний разделены, и это не украшательство.
    ///
    /// Одиннадцать строк в окно 780×700 не помещаются: последние две уходили
    /// под обрез, и о поглаживании с уводом курсора человек узнавал, только
    /// если догадывался прокрутить. Прокрутка тут страховка, а не способ
    /// показать содержимое.
    private var gesturesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepTitle(t("Как этим пользоваться"), subtitle: t("Вырез не отбирает фокус: активное приложение остаётся активным."))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    gesture("text.viewfinder", t("Выделите текст и нажмите ⌃⌥C"),
                            t("Захваченное появится над полем вопроса, команды — списком под ним"))
                    gesture("cursorarrow.rays", t("Наведите курсор на вырез"),
                            t("Мини-вид: что играет и когда ближайшая встреча"))
                    gesture("hand.tap.fill", t("Нажмите или потяните вниз"),
                            t("Панель целиком. Свайп вверх сворачивает её обратно"))
                    gesture("cursorarrow.click.badge.clock", t("Правая кнопка"),
                            t("Меню всех функций: ИИ, буфер, полка, таймер, нагрузка, суфлер"))
                    gesture("arrow.left.arrow.right", t("Свайп двумя пальцами"),
                            t("Предыдущий и следующий трек, не убирая курсор с выреза"))
                    gesture("pawprint.fill", t("Погладьте чёлку"),
                            t("Поводите курсором из стороны в сторону — вырез замурчит"))
                    gesture("arrow.down.left", t("Уведите курсор"),
                            t("Вырез свернётся сам — закрывать ничего не нужно"))
                }
            }
        }
    }

    /// Сочетания — своим шагом. Каждое правится прямо здесь: набирать его
    /// заново в настройках после того, как оно уже названо, — лишний шаг.
    private var shortcutsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepTitle(t("Сочетания клавиш"),
                      subtitle: t("Все на ⌃⌥: эту пару macOS не занимает ни под что. Любое можно сменить прямо здесь."))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    assistantHotKeyRow
                    clipboardHotKeyRow
                    shelfHotKeyRow
                    timerHotKeyRow
                    monitorHotKeyRow
                    teleprompterHotKeyRow
                    notesHotKeyRow
                }
            }
        }
    }

    /// Главное сочетание: захватить выделенное и спросить о нём модель.
    ///
    /// Показывается настоящее и правится на месте: набирать его заново
    /// в настройках после того, как оно уже названо здесь, — лишний шаг,
    /// а вписанное в текст оно к тому же врёт, стоит его сменить.
    private var assistantHotKeyRow: some View {
        WelcomeCard {
            HStack(spacing: 13) {
                WelcomeGlyph(symbol: "text.viewfinder", size: WelcomeStyle.tile)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Спросить о выделенном"))
                        .font(.system(size: WelcomeStyle.title, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(slotsHint)
                        .font(.system(size: WelcomeStyle.detail, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HotKeyRecorder(
                    spec: Binding(
                        get: { settings.assistantHotKey },
                        set: { spec in
                            settings.assistantHotKey = spec
                            onHotKeysChanged()
                        }
                    ),
                    placeholder: t("Не назначено")
                )
                .frame(width: WelcomeStyle.shortcutField.width,
                       height: WelcomeStyle.shortcutField.height)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    /// История буфера вызывается своим сочетанием — его тоже показываем
    /// настоящим и правим на месте.
    private var clipboardHotKeyRow: some View {
        WelcomeCard {
            HStack(spacing: 13) {
                WelcomeGlyph(symbol: "doc.on.clipboard", size: WelcomeStyle.tile)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("История буфера обмена"))
                        .font(.system(size: WelcomeStyle.title, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(clipboardSlotsHint)
                        .font(.system(size: WelcomeStyle.detail, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HotKeyRecorder(
                    spec: Binding(
                        get: { settings.clipboardHotKey },
                        set: { spec in
                            settings.clipboardHotKey = spec
                            onHotKeysChanged()
                        }
                    ),
                    placeholder: t("Не назначено")
                )
                .frame(width: WelcomeStyle.shortcutField.width,
                       height: WelcomeStyle.shortcutField.height)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    /// Полка: своё сочетание и объяснение, что файлы кладут перетаскиванием.
    private var shelfHotKeyRow: some View {
        WelcomeCard {
            HStack(spacing: 13) {
                WelcomeGlyph(symbol: "tray.full", size: WelcomeStyle.tile)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Полка для файлов"))
                        .font(.system(size: WelcomeStyle.title, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(shelfHint)
                        .font(.system(size: WelcomeStyle.detail, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HotKeyRecorder(
                    spec: Binding(
                        get: { settings.shelfHotKey },
                        set: { spec in
                            settings.shelfHotKey = spec
                            onHotKeysChanged()
                        }
                    ),
                    placeholder: t("Не назначено")
                )
                .frame(width: WelcomeStyle.shortcutField.width,
                       height: WelcomeStyle.shortcutField.height)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    /// Таймер: своё сочетание и подсказка про полоску в чёлке — иначе о ней
    /// узнают случайно.
    private var timerHotKeyRow: some View {
        WelcomeCard {
            HStack(spacing: 13) {
                WelcomeGlyph(symbol: "timer", size: WelcomeStyle.tile)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Таймер и секундомер"))
                        .font(.system(size: WelcomeStyle.title, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(t("Пока идёт, чёлка раздвигается счётом — нажмите по нему"))
                        .font(.system(size: WelcomeStyle.detail, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HotKeyRecorder(
                    spec: Binding(
                        get: { settings.timerHotKey },
                        set: { spec in
                            settings.timerHotKey = spec
                            onHotKeysChanged()
                        }
                    ),
                    placeholder: t("Не назначено")
                )
                .frame(width: WelcomeStyle.shortcutField.width,
                       height: WelcomeStyle.shortcutField.height)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    /// Заметки: единственная функция, у которой нет плитки в меню функций,
    /// — значит клавиша тут не удобство, а единственный способ записать
    /// мысль, не трогая мышь.
    ///
    /// Название и пояснение говорят про **ИИ**, а не про «заметки» вообще:
    /// заметки есть у всех, а имя записи, которое придумывает модель,
    /// и поиск по всему архиву её же силами — то, чего от заметок в вырезе
    /// никто не ждёт, и не сказать об этом значит не сказать ничего.
    private var notesHotKeyRow: some View {
        WelcomeCard {
            HStack(spacing: 13) {
                WelcomeGlyph(
                    symbol: "square.and.pencil",
                    tint: WelcomePalette.violet,
                    size: WelcomeStyle.tile
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Новая заметка с ИИ"))
                        .font(.system(size: WelcomeStyle.title, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(t("Клавиша открывает пустую заметку. Название ей придумает модель, а потом у неё же можно спросить по всем заметкам разом — ответит по вашим записям, а не по общим знаниям"))
                        .font(.system(size: WelcomeStyle.detail, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HotKeyRecorder(
                    spec: Binding(
                        get: { settings.notesHotKey },
                        set: { spec in
                            settings.notesHotKey = spec
                            onHotKeysChanged()
                        }
                    ),
                    placeholder: t("Не назначено")
                )
                .frame(width: WelcomeStyle.shortcutField.width,
                       height: WelcomeStyle.shortcutField.height)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    /// Нагрузка: сочетание и куда ведёт нажатие по показателю.
    /// Телесуфлер — единственное, чего в списке возможностей не угадать
    /// по названию: «текст под чёлкой» звучит странно, пока не сказано, что
    /// под чёлкой стоит камера.
    private var teleprompterHotKeyRow: some View {
        WelcomeCard {
            HStack(spacing: 13) {
                WelcomeGlyph(symbol: "text.alignleft", tint: WelcomePalette.violet, size: WelcomeStyle.tile)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Телесуфлер"))
                        .font(.system(size: WelcomeStyle.title, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(t("Текст под чёлкой — там, где камера. С оформлением и автопрокруткой: читая с середины экрана, смотришь мимо объектива"))
                        .font(.system(size: WelcomeStyle.detail, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HotKeyRecorder(
                    spec: Binding(
                        get: { settings.teleprompterHotKey },
                        set: { spec in
                            settings.teleprompterHotKey = spec
                            onHotKeysChanged()
                        }
                    ),
                    placeholder: t("Не назначено")
                )
                .frame(width: WelcomeStyle.shortcutField.width,
                       height: WelcomeStyle.shortcutField.height)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private var monitorHotKeyRow: some View {
        WelcomeCard {
            HStack(spacing: 13) {
                WelcomeGlyph(symbol: "gauge.with.dots.needle.67percent", size: WelcomeStyle.tile)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Нагрузка на систему"))
                        .font(.system(size: WelcomeStyle.title, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(t("Процессор, память и диск. Нажмите — откроется Мониторинг системы"))
                        .font(.system(size: WelcomeStyle.detail, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HotKeyRecorder(
                    spec: Binding(
                        get: { settings.monitorHotKey },
                        set: { spec in
                            settings.monitorHotKey = spec
                            onHotKeysChanged()
                        }
                    ),
                    placeholder: t("Не назначено")
                )
                .frame(width: WelcomeStyle.shortcutField.width,
                       height: WelcomeStyle.shortcutField.height)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private var shelfHint: String {
        settings.shelfEnabled
            ? t("Ведите файлы на чёлку. Обратно — перетаскиванием, насовсем")
            : t("Приём файлов выключен в настройках")
    }

    private var clipboardSlotsHint: String {
        let slots = settings.clipboardSlotModifiers
        guard slots != .off else {
            return t("Копирования запоминаются; клавиши номеров выключены в настройках")
        }
        return tf("Последние девять записей — %@", slots.title)
    }

    /// Сочетания команд перечисляются те, что назначены на самом деле.
    private var slotsHint: String {
        let assigned = settings.quickCommands.compactMap { $0.hotKey?.display }
        guard !assigned.isEmpty else {
            return t("Выделенное попадёт в панель разговора, команды — списком под полем")
        }
        return t("Команды напрямую: ") + assigned.joined(separator: ", ")
    }

    private func gesture(_ symbol: String, _ title: String, _ detail: String) -> some View {
        WelcomeCard {
            HStack(spacing: 13) {
                WelcomeGlyph(symbol: symbol, size: WelcomeStyle.tile)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: WelcomeStyle.title, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(.system(size: WelcomeStyle.detail, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    // MARK: Шаг 3 — доступы

    /// Строк здесь больше, чем помещается: у погоды разворачивается поиск
    /// города, и без прокрутки нижние карточки ушли бы под обрез — окно
    /// обрезает содержимое молча, с обеих сторон сразу.
    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepTitle(t("Что разрешить"),
                      subtitle: t("Без доступа приложение работает, но соответствующая часть молчит."))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(WelcomeModel.Permission.allCases) { permission in
                        permissionRow(permission)
                    }
                    weatherRow
                    launchRow
                    updatesRow
                    ollamaRow
                    Text(t("Доступ выдаётся один раз и переживает обновления приложения. Отказ система запоминает — вернуть его можно только в Системных настройках."))
                        .font(.system(size: WelcomeStyle.caption, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Погода — единственная часть, которой нужна геопозиция.
    ///
    /// Здесь же и выход для тех, кто её не отдаёт: названный город работает
    /// не хуже, а системного диалога о положении тогда не будет вовсе.
    /// Сказать об этом надо именно на шаге доступов — иначе человек откажет
    /// системе и решит, что погода просто сломана.
    private var weatherRow: some View {
        let byPlace = settings.weatherSource == .place

        return WelcomeCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 13) {
                    WelcomeGlyph(symbol: "cloud.sun.fill", tint: WelcomePalette.cyan, size: WelcomeStyle.tile)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Погода"))
                            .font(.system(size: WelcomeStyle.title, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(byPlace
                             ? t("По названному городу — доступ к геопозиции не нужен вовсе")
                             : t("По геопозиции. Не хотите её отдавать — назовите город"))
                            .font(.system(size: WelcomeStyle.detail, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Button(byPlace ? t("По геопозиции") : t("Указать город")) {
                        settings.weatherSource = byPlace ? .location : .place
                        placeSearch.reset()
                        weather.placeChanged()
                    }
                    .buttonStyle(WelcomeGhostButton())
                }
                if byPlace { placeField }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .animation(.easeOut(duration: 0.25), value: byPlace)
    }

    @ViewBuilder
    private var placeField: some View {
        if let place = settings.weatherPlace {
            HStack(spacing: 8) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(WelcomePalette.mint)
                Text(place.title)
                    .font(.system(size: WelcomeStyle.body, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Button(t("Сменить")) {
                    settings.weatherPlace = nil
                    placeSearch.reset()
                }
                .buttonStyle(WelcomeGhostButton())
            }
        } else {
            HStack(spacing: 8) {
                TextField(t("Название города"), text: $placeSearch.query)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: WelcomeStyle.body, design: .rounded))
                    // По нажатию Enter, а не по каждой букве: иначе запрос
                    // уходил бы на каждое нажатие клавиши.
                    .onSubmit { placeSearch.search() }
                Button(t("Найти")) { placeSearch.search() }
                    .buttonStyle(WelcomeGhostButton())
                    .disabled(placeSearch.query.trimmingCharacters(in: .whitespaces).count < 2)
            }

            if let message = placeSearch.message {
                Text(message)
                    .font(.system(size: WelcomeStyle.caption, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
            }

            // Четыре строки, а не весь список: карточка на шаге доступов
            // не должна вырастать во весь экран, а тёзки идут первыми.
            ForEach(placeSearch.results.prefix(4)) { found in
                Button {
                    settings.weatherPlace = found
                    placeSearch.reset()
                    weather.placeChanged()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "mappin")
                            .font(.system(size: WelcomeStyle.caption))
                            .foregroundStyle(Color.white.opacity(0.45))
                        Text(found.title)
                            .font(.system(size: WelcomeStyle.detail, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.8))
                        Spacer(minLength: 8)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func permissionRow(_ permission: WelcomeModel.Permission) -> some View {
        let state = model.state(of: permission)
        let needed = model.isRequired(permission) && state != .granted

        return WelcomeCard(highlighted: needed) {
            HStack(spacing: 13) {
                WelcomeGlyph(
                    symbol: permission.icon,
                    tint: state == .granted ? WelcomePalette.mint : WelcomePalette.cyan,
                    size: WelcomeStyle.tile
                )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(permission.title)
                            .font(.system(size: WelcomeStyle.title, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        stateBadge(state)
                    }
                    Text(permission.explanation)
                        .font(.system(size: WelcomeStyle.detail, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                // У выданного доступа кнопки нет вовсе: нажимать нечего,
                // а надпись «Выдан» второй раз повторяла бы значок состояния.
                if state == .granted {
                    Image(systemName: "checkmark")
                        .font(.system(size: WelcomeStyle.title, weight: .semibold))
                        .foregroundStyle(WelcomePalette.mint)
                        .padding(.trailing, 8)
                } else {
                    Button(model.actionTitle(for: permission)) {
                        model.act(on: permission)
                    }
                    .buttonStyle(WelcomeGhostButton())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
        }
        .animation(.easeOut(duration: 0.3), value: state)
    }

    private func stateBadge(_ state: WelcomeModel.PermissionState) -> some View {
        let tint: Color
        switch state {
        case .granted: tint = WelcomePalette.mint
        case .notAsked: tint = Color.white.opacity(0.45)
        case .denied: tint = WelcomePalette.amber
        }
        return HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 5, height: 5)
            Text(state.label)
                .font(.system(size: WelcomeStyle.micro, weight: .medium, design: .monospaced))
                .foregroundStyle(tint)
        }
    }

    private var launchRow: some View {
        WelcomeCard {
            HStack(spacing: 13) {
                WelcomeGlyph(symbol: "power", tint: WelcomePalette.violet, size: WelcomeStyle.tile)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Запускать при входе в систему"))
                        .font(.system(size: WelcomeStyle.title, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(t("Вырез должен быть на месте с первой секунды — иначе о нём забываешь"))
                        .font(.system(size: WelcomeStyle.detail, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                // Подпись скрыта визуально — слева уже стоит своя строка, —
                // но в дереве доступности остаётся: без неё выключатель
                // объявлялся безымянным.
                Toggle(t("Запускать при входе в систему"), isOn: Binding(
                    get: { launchAtLogin.isEnabled },
                    set: { launchAtLogin.isEnabled = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(WelcomePalette.cyan)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    /// Обновления — не разрешение, а единственное, кроме погоды, обращение
    /// приложения в интернет. Сказать об этом надо там же, где спрашивают
    /// про доступы: узнать о такой проверке из настроек, наткнувшись на неё
    /// случайно, — худший способ о ней узнать.
    private var updatesRow: some View {
        WelcomeCard {
            HStack(spacing: 13) {
                WelcomeGlyph(symbol: "arrow.down.circle.fill", tint: WelcomePalette.mint, size: WelcomeStyle.tile)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Обновляться самому"))
                        .font(.system(size: WelcomeStyle.title, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(t("Раз в сутки спрашивает GitHub о новой версии и скачивает её фоном. Ставится по нажатию"))
                        .font(.system(size: WelcomeStyle.detail, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                // Подпись скрыта визуально, но в дереве доступности остаётся:
                // без неё выключатель объявлялся бы безымянным.
                Toggle(t("Обновляться самому"), isOn: settings.binding(\.autoUpdateEnabled))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(WelcomePalette.cyan)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    /// Ollama — не разрешение, а отдельная программа, и без неё запросы
    /// к модели просто не заработают. Сказать об этом надо там же, где
    /// человек настраивает всё остальное: иначе он найдёт пустую команду
    /// и решит, что она сломана.
    private var ollamaRow: some View {
        WelcomeCard {
            HStack(spacing: 13) {
                WelcomeGlyph(symbol: "sparkles", tint: WelcomePalette.mint, size: WelcomeStyle.tile)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Запросы к модели — через Ollama"))
                        .font(.system(size: WelcomeStyle.title, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(t("Отдельная бесплатная программа: держит модель на вашем компьютере, наружу ничего не уходит. Остальные команды работают и без неё."))
                        .font(.system(size: WelcomeStyle.detail, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("ollama.com") {
                    guard let url = URL(string: "https://ollama.com") else { return }
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(WelcomeGhostButton())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    // MARK: Шаг 4 — готово

    private var doneStep: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(WelcomePalette.mint.opacity(0.14))
                    .frame(width: WelcomeStyle.markWell, height: WelcomeStyle.markWell)
                    .overlay(Circle().strokeBorder(WelcomePalette.mint.opacity(0.35), lineWidth: 1))
                Image(systemName: "checkmark")
                    .font(.system(size: WelcomeStyle.mark, weight: .semibold))
                    .foregroundStyle(WelcomePalette.mint)
            }

            VStack(spacing: 8) {
                Text(t("Всё готово"))
                    .font(.system(size: WelcomeStyle.finale, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(model.pendingCount == 0
                     ? t("Доступы выданы. Наведите курсор на вырез — и он раскроется.")
                     : tf("Осталось невыданных доступов: %d. ", model.pendingCount)
                       + t("Их можно выдать позже — в настройках или на прошлом шаге."))
                    .font(.system(size: WelcomeStyle.title, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460)
            }

            HStack(spacing: 10) {
                hintCard("menubar.arrow.up.rectangle", t("Значок в строке меню"),
                         t("Настройки, обновление трека и выход"))
                hintCard("sparkles", t("Это окно"),
                         t("Открывается снова из меню — «Знакомство»"))
            }
        }
    }

    private func hintCard(_ symbol: String, _ title: String, _ detail: String) -> some View {
        WelcomeCard {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: WelcomeStyle.glyph, weight: .medium))
                    .foregroundStyle(WelcomePalette.cyan)
                Text(title)
                    .font(.system(size: WelcomeStyle.body, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: WelcomeStyle.caption, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: WelcomeStyle.hintCardWidth, alignment: .leading)
        }
    }

    // MARK: - Общее

    private func stepTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: WelcomeStyle.chapter, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: WelcomeStyle.title, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if !model.isLastStep {
                Button(t("Пропустить")) { onFinish() }
                    .buttonStyle(WelcomeGhostButton(isQuiet: true))
            }
            Spacer(minLength: 0)
            if model.canGoBack {
                Button(t("Назад")) { model.back() }
                    .buttonStyle(WelcomeGhostButton())
            }
            Button(model.isLastStep ? t("Начать") : t("Дальше")) {
                if model.isLastStep { onFinish() } else { model.next() }
            }
            .buttonStyle(WelcomePrimaryButton())
        }
    }
}
