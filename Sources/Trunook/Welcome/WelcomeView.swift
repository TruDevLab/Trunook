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
    /// Сочетания заданы пользователем — после правки их надо
    /// перерегистрировать в системе.
    let onHotKeysChanged: () -> Void
    let onFinish: () -> Void

    static let size = CGSize(width: 780, height: 700)

    var body: some View {
        ZStack {
            WelcomeBackground()
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
                    .font(.system(size: 10, weight: .medium))
                Text(settings.language.title)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
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
                        .fill(isCurrent ? AnyShapeStyle(WelcomePalette.accent)
                                        : AnyShapeStyle(Color.white.opacity(0.16)))
                        .frame(width: isCurrent ? 26 : 12, height: 4)
                        .contentShape(Capsule().inset(by: -6))
                }
                .buttonStyle(.plain)
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
        case .permissions: permissionsStep
        case .done: doneStep
        }
    }

    // MARK: Шаг 1 — что это

    private var introStep: some View {
        VStack(spacing: 22) {
            VStack(spacing: 9) {
                Text("Trunook")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(WelcomePalette.accent)
                Text(t("Вырез MacBook становится центром управления"))
                    .font(.system(size: 14.5, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.62))
            }
            WelcomeNotchDemo()
            featureRow
        }
    }

    /// Два ряда по четыре, а не один длинный: восемь плиток в строку шире
    /// окна, и содержимое, которое шире окна, раздвигает его — по краям
    /// обрезались и заголовок, и кнопки.
    private var featureRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                feature("music.note", t("Музыка"), WelcomePalette.violet)
                feature("calendar", t("Календарь"), WelcomePalette.cyan)
                feature("square.grid.2x2.fill", t("Команды"), WelcomePalette.mint)
                feature("video.fill", t("Встречи"), WelcomePalette.violet)
            }
            HStack(spacing: 10) {
                feature("doc.on.clipboard.fill", t("Буфер"), WelcomePalette.cyan)
                feature("tray.full.fill", t("Полка"), WelcomePalette.violet)
                feature("cloud.sun.fill", t("Погода"), WelcomePalette.cyan)
                feature("bolt.fill", t("Питание"), WelcomePalette.mint)
            }
        }
    }

    private func feature(_ symbol: String, _ title: String, _ tint: Color) -> some View {
        WelcomeCard {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.72))
            }
            .frame(width: 96, height: 62)
        }
    }

    // MARK: Шаг 2 — управление

    private var gesturesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            stepTitle(t("Как этим пользоваться"), subtitle: t("Вырез не отбирает фокус: активное приложение остаётся активным."))
            // Прокрутка — страховка, а не задумка: строк девять, и каждая
            // новая раньше выдавливала содержимое за края окна в обе стороны.
            // Список должен помещаться и без прокрутки, но если не поместится,
            // пусть лучше прокручивается, чем обрезает кнопки.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 6) {
                    gesture("cursorarrow.rays", t("Наведите курсор на вырез"),
                            t("Мини-вид: что играет и когда ближайшая встреча"))
                    gesture("hand.tap.fill", t("Нажмите или потяните вниз"),
                            t("Панель целиком. Свайп вверх сворачивает её обратно"))
                    gesture("cursorarrow.click.badge.clock", t("Правая кнопка"),
                            t("Меню всех функций: главный экран, команды, буфер, полка"))
                    gesture("arrow.left.arrow.right", t("Свайп двумя пальцами"),
                            t("Предыдущий и следующий трек, не убирая курсор с выреза"))
                    menuHotKeyRow
                    clipboardHotKeyRow
                    shelfHotKeyRow
                    gesture("pawprint.fill", t("Погладьте чёлку"),
                            t("Поводите курсором из стороны в сторону — вырез замурчит"))
                    gesture("arrow.down.left", t("Уведите курсор"),
                            t("Вырез свернётся сам — закрывать ничего не нужно"))
                }
            }
        }
    }

    /// Сочетание меню показывается настоящее и правится на месте: набирать
    /// его заново в настройках после того, как оно уже названо здесь, —
    /// лишний шаг, а вписанное в текст оно к тому же врёт, стоит его сменить.
    private var menuHotKeyRow: some View {
        WelcomeCard {
            HStack(spacing: 13) {
                WelcomeGlyph(symbol: "command", size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Меню быстрых команд"))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(slotsHint)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HotKeyRecorder(
                    spec: Binding(
                        get: { settings.menuHotKey },
                        set: { spec in
                            settings.menuHotKey = spec
                            onHotKeysChanged()
                        }
                    ),
                    placeholder: t("Не назначено")
                )
                .frame(width: 132, height: 26)
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
                WelcomeGlyph(symbol: "doc.on.clipboard", size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("История буфера обмена"))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(clipboardSlotsHint)
                        .font(.system(size: 12, design: .rounded))
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
                .frame(width: 132, height: 26)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    /// Полка: своё сочетание и объяснение, что файлы кладут перетаскиванием.
    private var shelfHotKeyRow: some View {
        WelcomeCard {
            HStack(spacing: 13) {
                WelcomeGlyph(symbol: "tray.full", size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Полка для файлов"))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(shelfHint)
                        .font(.system(size: 12, design: .rounded))
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
                .frame(width: 132, height: 26)
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

    /// Сочетания слотов перечисляются те, что назначены на самом деле.
    private var slotsHint: String {
        let assigned = settings.quickCommands.compactMap { $0.hotKey?.display }
        guard !assigned.isEmpty else {
            return t("Слоты запускаются из меню — сочетания для них задаются в настройках")
        }
        return t("Слоты напрямую: ") + assigned.joined(separator: ", ")
    }

    private func gesture(_ symbol: String, _ title: String, _ detail: String) -> some View {
        WelcomeCard {
            HStack(spacing: 13) {
                WelcomeGlyph(symbol: symbol, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(detail)
                        .font(.system(size: 12, design: .rounded))
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

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            stepTitle(t("Что разрешить"),
                      subtitle: t("Без доступа приложение работает, но соответствующая часть молчит."))
            VStack(spacing: 8) {
                ForEach(WelcomeModel.Permission.allCases) { permission in
                    permissionRow(permission)
                }
            }
            launchRow
            ollamaRow
            Text(t("Доступ выдаётся один раз и переживает обновления приложения. Отказ система запоминает — вернуть его можно только в Системных настройках."))
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
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
                    size: 32
                )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(permission.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        stateBadge(state)
                    }
                    Text(permission.explanation)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                // У выданного доступа кнопки нет вовсе: нажимать нечего,
                // а надпись «Выдан» второй раз повторяла бы значок состояния.
                if state == .granted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
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
        case .denied: tint = Color.orange
        }
        return HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 5, height: 5)
            Text(state.label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(tint)
        }
    }

    private var launchRow: some View {
        WelcomeCard {
            HStack(spacing: 13) {
                WelcomeGlyph(symbol: "power", tint: WelcomePalette.violet, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Запускать при входе в систему"))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(t("Вырез должен быть на месте с первой секунды — иначе о нём забываешь"))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
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

    /// Ollama — не разрешение, а отдельная программа, и без неё запросы
    /// к модели просто не заработают. Сказать об этом надо там же, где
    /// человек настраивает всё остальное: иначе он найдёт пустую команду
    /// и решит, что она сломана.
    private var ollamaRow: some View {
        WelcomeCard {
            HStack(spacing: 13) {
                WelcomeGlyph(symbol: "sparkles", tint: WelcomePalette.mint, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Запросы к модели — через Ollama"))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(t("Отдельная бесплатная программа: держит модель на вашем компьютере, наружу ничего не уходит. Остальные команды работают и без неё."))
                        .font(.system(size: 12, design: .rounded))
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
                    .frame(width: 92, height: 92)
                    .overlay(Circle().strokeBorder(WelcomePalette.mint.opacity(0.35), lineWidth: 1))
                Image(systemName: "checkmark")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(WelcomePalette.mint)
            }
            .shadow(color: WelcomePalette.mint.opacity(0.3), radius: 24)

            VStack(spacing: 8) {
                Text(t("Всё готово"))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(model.pendingCount == 0
                     ? t("Доступы выданы. Наведите курсор на вырез — и он раскроется.")
                     : tf("Осталось невыданных доступов: %d. ", model.pendingCount)
                       + t("Их можно выдать позже — в настройках или на прошлом шаге."))
                    .font(.system(size: 13.5, design: .rounded))
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
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(WelcomePalette.cyan)
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 11.5, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 216, alignment: .leading)
        }
    }

    // MARK: - Общее

    private func stepTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(subtitle)
                .font(.system(size: 13, design: .rounded))
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
