import AppKit
import SwiftUI

/// Состояние шага «Помощник»: отвечает ли выбранный сервер.
///
/// Отдельным объектом, а не полем вида: `@State` в этом SDK недоступен,
/// а проверка идёт по сети и возвращается позже, чем строится вёрстка.
final class WelcomeAI: ObservableObject {
    /// Раскрыт ли выбор провайдера и поле ключа.
    ///
    /// Свёрнуто: человеку, который просто хочет, чтобы заработало, двенадцать
    /// провайдеров и поле ключа на первом экране мешают. Тому, у кого свой
    /// сервер, достаточно одной строки внизу.
    ///
    /// В объекте, а не в поле вида: `@State` в этом SDK недоступен,
    /// а раскрытие обязано пережить перерисовку.
    @Published var showsAdvanced = false
}

/// Шаг знакомства, на котором заводят помощника.
///
/// Разговор про модель был раскидан по трём местам: карточка со ссылкой
/// на ollama.com в доступах, выбор модели в настройках, а скачать её было
/// нечем, кроме терминала.
///
/// Шаг начинается **не с настройки, а с того, что она даёт**. «Модель» —
/// слово из документации: оно ничего не обещает и настраивать себя не зовёт.
/// Человек соглашается на три минуты возни, когда видит, что получит
/// взамен, — поэтому сверху три обещания, а сервер и модели ниже.
///
/// Ollama здесь рекомендована, а не обязательна: приложение работает
/// с дюжиной провайдеров, и человек, у которого уже есть свой сервер или
/// ключ, не должен ставить вторую программу ради того, что у него есть.
struct WelcomeAIPage: View {
    @ObservedObject var settings: Settings
    @ObservedObject var state: WelcomeAI
    @ObservedObject var models: ModelList
    @ObservedObject var installer: ModelInstaller

    @ObservedObject var engine: OllamaEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            title
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    promises
                    engineCard
                    offersCard
                    advancedRow
                    footnote
                }
            }
        }
        .onAppear {
            engine.refresh()
            models.refreshIfNeeded()
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t("Помощник, который делает"))
                .font(.system(size: WelcomeStyle.chapter, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text(t("Один раз поставьте модель — и вырез начнёт отвечать, искать и делать дела."))
                .font(.system(size: WelcomeStyle.detail, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Что это даёт

    /// Четыре обещания вместо описания устройства.
    ///
    /// Каждое — про то, что человек получит, а не про то, что мы включим.
    /// «Векторный поиск по эмбеддингам» ему ничего не обещает; «найдётся,
    /// даже если вы забыли слова» — обещает.
    ///
    /// Прежде их было три, и все три про заметки: экран звался «Заметки,
    /// которые отвечают». С тех пор помощник научился действовать —
    /// календарь, напоминания, таймер, погода, — заговорил голосом
    /// и стал писать под диктовку. Экран про одни заметки обещал вчетверо
    /// меньше, чем даёт.
    ///
    /// Связи с заметками ушли второй фразой к поиску: это одно умение
    /// с двух сторон, а пятая строка растила карточку, не добавляя нового.
    private var promises: some View {
        WelcomeCard {
            VStack(alignment: .leading, spacing: 10) {
                promise(
                    symbol: "bubble.left.and.text.bubble.right",
                    tint: WelcomePalette.mint,
                    title: t("Спросить, не отрываясь"),
                    detail: t("Вопрос голосом или текстом — ответ прямо под чёлкой, поверх любого окна.")
                )
                promise(
                    symbol: "wand.and.stars",
                    tint: WelcomePalette.amber,
                    title: t("Поручить, а не делать самому"),
                    detail: t("Встреча, напоминание, таймер, погода, дела на день. Всё, что записывается, — только после вашего подтверждения.")
                )
                promise(
                    symbol: "sparkle.magnifyingglass",
                    tint: WelcomePalette.cyan,
                    title: t("Найти забытое"),
                    detail: t("Поиск по смыслу: заметка найдётся, даже если вы не помните из неё ни одного слова. Записи об одном и том же свяжутся сами.")
                )
                promise(
                    symbol: "mic.fill",
                    tint: WelcomePalette.violet,
                    title: t("Говорить вместо печати"),
                    detail: t("Диктовка в поле вопроса и в заметку, а запись встречи станет заметкой с расшифровкой.")
                )
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private func promise(symbol: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
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
            Spacer(minLength: 0)
        }
    }

    // MARK: - Движок

    /// Что такое Ollama, в каком она состоянии и одна кнопка по делу.
    ///
    /// Сказано прямо: программа чужая, бесплатная, с открытым кодом, живёт
    /// в строке меню и остаётся на машине, даже если Trunook удалить.
    /// Поставить её втихую было бы проще, но человек должен знать, что
    /// у него на компьютере появилось.
    private var engineCard: some View {
        WelcomeCard {
            HStack(alignment: .top, spacing: 13) {
                WelcomeGlyph(
                    symbol: "shippingbox.fill",
                    tint: WelcomePalette.amber,
                    size: WelcomeStyle.tile
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("Движок моделей"))
                        .font(.system(size: WelcomeStyle.title, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(engine.line.text)
                        .font(.system(size: WelcomeStyle.detail, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(t("Ollama — бесплатная программа с открытым кодом. Она запускает модели прямо на вашем компьютере и остаётся в строке меню."))
                        .font(.system(size: WelcomeStyle.caption, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                    if case let .downloading(share) = engine.state {
                        ProgressView(value: share).controlSize(.small).frame(width: 160)
                    }
                }
                Spacer(minLength: 8)
                engineButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder
    private var engineButton: some View {
        switch engine.line.action {
        case .none, .busy:
            EmptyView()
        case .install:
            Button(t("Установить")) { engine.install() }
                .buttonStyle(WelcomeGhostButton())
        case .start:
            Button(t("Запустить")) { engine.start() }
                .buttonStyle(WelcomeGhostButton())
        case .check:
            Button(t("Проверить")) { engine.refresh() }
                .buttonStyle(WelcomeGhostButton())
        case .cancel:
            Button(t("Отменить")) { engine.cancelInstall() }
                .buttonStyle(WelcomeGhostButton())
        case .reveal:
            Button(t("Показать в Finder")) { engine.revealImage() }
                .buttonStyle(WelcomeGhostButton())
        case .copyCommand:
            Button(t("Скопировать команду")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(OllamaApp.serveCommand, forType: .string)
            }
            .buttonStyle(WelcomeGhostButton())
        }
    }

    // MARK: - Свой сервер

    /// Одна строка внизу для тех, у кого свой сервер или облачный ключ.
    ///
    /// Прежде выбор из двенадцати провайдеров стоял тут первым делом —
    /// и первым же вопросом человеку, который не знает, что такое провайдер.
    /// Теперь он есть, но не на дороге.
    private var advancedRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                state.showsAdvanced.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: state.showsAdvanced ? "chevron.down" : "chevron.right")
                        .font(.system(size: WelcomeStyle.caption, weight: .semibold))
                    Text(t("У меня свой сервер или ключ"))
                        .font(.system(size: WelcomeStyle.detail, design: .rounded))
                }
                .foregroundStyle(Color.white.opacity(0.55))
            }
            .buttonStyle(.plain)

            if state.showsAdvanced {
                providerPicker
                if settings.aiProvider.usesKey { keyField }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var providerPicker: some View {
        Picker("", selection: Binding(
            get: { settings.aiProvider },
            set: { choose($0) }
        )) {
            ForEach(AIProvider.allCases) { provider in
                Text(provider == .ollama ? tf("%@ — рекомендуем", provider.title) : provider.title)
                    .tag(provider)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: 300, alignment: .leading)
        .accessibilityLabel(t("Кто отвечает"))
    }

    /// Ключ спрашиваем только у тех, кому он нужен: у местного сервера
    /// его нет вовсе, и пустое поле рядом с ним читалось бы как
    /// незаполненная обязательная строка.
    private var keyField: some View {
        VStack(alignment: .leading, spacing: 4) {
            SecureField(t("Ключ доступа"), text: Binding(
                get: { settings.apiKey(for: settings.aiProvider) },
                set: { settings.setAPIKey($0, for: settings.aiProvider) }
            ))
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 300)
            Text(t("Ключ хранится на вашем компьютере и уходит только выбранному серверу."))
                .font(.system(size: WelcomeStyle.caption, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.4))
        }
    }

    /// Смена провайдера: включаем выбранного и делаем его основным.
    ///
    /// Прежнего не выключаем — он мог быть настроен и пригодиться командам;
    /// «основной» и «включён» здесь разные вещи.
    private func choose(_ provider: AIProvider) {
        settings.setProvider(provider, enabled: true)
        settings.aiProvider = provider
        engine.refresh()
        models.refresh()
    }

    // MARK: - Модели

    /// Что человек получит: три разряда по силам его машины и модель
    /// для заметок.
    ///
    /// Список виден **до** того, как движок поднялся, — без кнопок.
    /// В этом и смысл экрана: сперва показать, что будет, а уже потом
    /// просить согласия поставить чужую программу.
    private var offersCard: some View {
        WelcomeCard {
            VStack(alignment: .leading, spacing: 10) {
                if !engine.state.isRunning {
                    Text(t("Сначала поставим движок — без него моделям нечем работать."))
                        .font(.system(size: WelcomeStyle.caption, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                ForEach(offers) { row in
                    offerRow(row)
                }
                if let pair = pairToInstall, engine.state.isRunning {
                    Button(t("Установить рекомендованное")) {
                        installer.enqueue(pair)
                        if let chat = pair.first { settings.setAPIModel(chat, for: .ollama) }
                    }
                    .buttonStyle(WelcomeGhostButton())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private var offers: [ModelOfferRow] {
        ModelCatalogue.rows(
            on: MachineResources.current(),
            installed: models.models(of: .ollama),
            selected: settings.apiModel(for: .ollama),
            installing: installer.installing,
            share: share,
            queued: installer.waiting
        )
    }

    /// Что осталось поставить из рекомендованного. `nil` — всё уже стоит.
    private var pairToInstall: [String]? {
        let pair = ModelCatalogue.recommendedPair(on: MachineResources.current())
        let installed = models.models(of: .ollama)
        let left = pair.filter { !RecommendedModel.isInstalled($0, among: installed) }
        return left.isEmpty ? nil : pair
    }

    /// Одна строка предложения — стеклянная.
    ///
    /// Состав строки берётся тот же, что и в настройках
    /// (`ModelCatalogue.rows`), а вид здесь свой: настройки рисуют формой
    /// с системными цветами, знакомство — белым по стеклу, и один вид
    /// на оба экрана был бы выдумкой.
    private func offerRow(_ row: ModelOfferRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.offer.title)
                        .font(.system(size: WelcomeStyle.detail, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    if let mark = badgeText(row.badge) {
                        Text(mark)
                            .font(.system(size: WelcomeStyle.caption, weight: .semibold, design: .rounded))
                            .foregroundStyle(WelcomePalette.mint)
                    }
                }
                Text(row.offer.detail)
                    .font(.system(size: WelcomeStyle.caption, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                if let warning = row.warning {
                    Text(warning)
                        .font(.system(size: WelcomeStyle.caption, design: .rounded))
                        .foregroundStyle(WelcomePalette.amber)
                }
            }
            Spacer(minLength: 8)
            Text(row.offer.sizeText)
                .font(.system(size: WelcomeStyle.caption, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.4))
            offerControl(row)
        }
        .opacity(row.badge == .heavy ? 0.55 : 1)
    }

    private func badgeText(_ badge: ModelOfferRow.Badge) -> String? {
        switch badge {
        case .recommended: return t("рекомендуем")
        case .selected: return t("отвечает")
        case .installed: return t("скачана")
        case .none, .heavy: return nil
        }
    }

    @ViewBuilder
    private func offerControl(_ row: ModelOfferRow) -> some View {
        // Пока движок не поднялся, список показывает состав, но нажимать
        // в нём нечего: качать некуда.
        if engine.state.isRunning {
            switch row.action {
            case .none, .blocked:
                EmptyView()
            case .install:
                Button(t("Скачать")) {
                    installer.enqueue([row.offer.tag])
                    settings.setAPIModel(row.offer.tag, for: .ollama)
                }
                .buttonStyle(WelcomeGhostButton())
            case .select:
                Button(t("Отвечать ею")) { settings.setAPIModel(row.offer.tag, for: .ollama) }
                    .buttonStyle(WelcomeGhostButton())
            case let .installing(value):
                HStack(spacing: 6) {
                    ProgressView(value: value).controlSize(.small).frame(width: 90)
                    Text(tf("%d%%", Int(value * 100)))
                        .font(.system(size: WelcomeStyle.caption, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .monospacedDigit()
                }
            case .queued:
                Text(t("в очереди"))
                    .font(.system(size: WelcomeStyle.caption, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        }
    }

    private var share: Double {
        if case .pulling(let value) = installer.state { return value }
        return 0
    }

    private var footnote: some View {
        Text(t("Всё это можно изменить потом в настройках. Скачивание идёт в фоне — окно можно закрыть."))
            .font(.system(size: WelcomeStyle.caption, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.4))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
