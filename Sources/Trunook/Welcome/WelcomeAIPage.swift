import AppKit
import SwiftUI

/// Состояние шага «Помощник»: отвечает ли выбранный сервер.
///
/// Отдельным объектом, а не полем вида: `@State` в этом SDK недоступен,
/// а проверка идёт по сети и возвращается позже, чем строится вёрстка.
final class WelcomeAI: ObservableObject {
    enum Reach: Equatable {
        case unknown
        case checking
        case up
        case down
    }

    @Published private(set) var reach: Reach = .unknown

    private let client = ModelClient()
    private let settings: Settings

    init(settings: Settings = .shared) {
        self.settings = settings
    }

    /// Спрашивает сервер, жив ли он.
    ///
    /// «Не установлена» и «установлена, но не запущена» человек со стороны
    /// приложения не различает — снаружи и то и другое выглядит как молчание.
    /// Поэтому состояние одно, и совет один.
    func check() {
        reach = .checking
        client.ping(settings.aiProvider) { [weak self] alive in
            DispatchQueue.main.async { self?.reach = alive ? .up : .down }
        }
    }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            title
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    promises
                    providerCard
                    if state.reach == .up {
                        modelCard(
                            title: t("Отвечает на вопросы"),
                            symbol: "text.bubble",
                            tint: WelcomePalette.mint,
                            kind: .chat,
                            recommended: RecommendedModel.chat,
                            selection: Binding(
                                get: { settings.apiModel(for: settings.aiProvider) },
                                set: { settings.setAPIModel($0, for: settings.aiProvider) }
                            )
                        )
                        modelCard(
                            title: t("Считает смысл заметок"),
                            symbol: "point.3.filled.connected.trianglepath.dotted",
                            tint: WelcomePalette.violet,
                            kind: .embedding,
                            recommended: RecommendedModel.embed,
                            selection: Binding(
                                get: {
                                    ModelRef.parse(settings.embedModel, fallback: settings.aiProvider)?.name ?? ""
                                },
                                set: {
                                    settings.embedModel = ModelRef(
                                        provider: settings.aiProvider,
                                        name: $0
                                    ).stored
                                }
                            )
                        )
                    }
                    footnote
                }
            }
        }
        .onAppear {
            state.check()
            models.refreshIfNeeded()
        }
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t("Заметки, которые отвечают"))
                .font(.system(size: WelcomeStyle.chapter, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text(t("Один раз подключите модель — и вырез начнёт отвечать, искать и связывать."))
                .font(.system(size: WelcomeStyle.detail, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Что это даёт

    /// Три обещания вместо описания устройства.
    ///
    /// Каждое — про то, что человек получит, а не про то, что мы включим.
    /// «Векторный поиск по эмбеддингам» ему ничего не обещает; «найдётся,
    /// даже если вы забыли слова» — обещает.
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
                    symbol: "sparkle.magnifyingglass",
                    tint: WelcomePalette.cyan,
                    title: t("Найти забытое"),
                    detail: t("Поиск по смыслу: заметка найдётся, даже если вы не помните из неё ни одного слова.")
                )
                promise(
                    symbol: "point.3.filled.connected.trianglepath.dotted",
                    tint: WelcomePalette.violet,
                    title: t("Увидеть связи"),
                    detail: t("Записи об одном и том же свяжутся сами — и в приложении, и в графе Obsidian.")
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

    // MARK: - Кто отвечает

    /// Выбор провайдера.
    ///
    /// Ollama помечена рекомендованной — она бесплатна и никуда ничего
    /// не отправляет, — но список открыт: у человека может быть свой сервер
    /// в сети или ключ к облачному. Заставлять его ставить вторую программу
    /// ради того, что у него уже есть, незачем.
    private var providerCard: some View {
        WelcomeCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 13) {
                    WelcomeGlyph(symbol: "server.rack", tint: WelcomePalette.amber, size: WelcomeStyle.tile)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Кто отвечает"))
                            .font(.system(size: WelcomeStyle.title, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(providerText)
                            .font(.system(size: WelcomeStyle.detail, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    providerControls
                }

                providerPicker

                if settings.aiProvider.usesKey {
                    keyField
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
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

    /// Ключ спрашиваем здесь только у тех, кому он нужен: у местного сервера
    /// его нет вовсе, и пустое поле рядом с ним читалось бы как незаполненная
    /// обязательная строка.
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

    @ViewBuilder
    private var providerControls: some View {
        if state.reach == .up {
            Toggle("", isOn: Binding(
                get: { settings.ollamaEnabled },
                set: { settings.ollamaEnabled = $0 }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel(t("Отвечать моделью"))
        } else {
            // Ставить нужно только местную программу; облачному провайдеру
            // качать нечего — ему нужен ключ, и он спрашивается ниже.
            if settings.aiProvider == .ollama {
                Button(t("Скачать")) {
                    guard let url = URL(string: "https://ollama.com/download") else { return }
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(WelcomeGhostButton())
            }
            Button(t("Проверить")) { state.check() }
                .buttonStyle(WelcomeGhostButton())
                .disabled(state.reach == .checking)
        }
    }

    private var providerText: String {
        switch state.reach {
        case .unknown, .checking:
            return t("Проверяю, отвечает ли…")
        case .up:
            return settings.aiProvider.isLocal
                ? t("Отвечает. Всё считается на вашем компьютере, наружу ничего не уходит.")
                : t("Отвечает. Вопросы и заметки уходят выбранному серверу.")
        case .down:
            return settings.aiProvider == .ollama
                ? t("Не отвечает. Ollama бесплатна: поставьте её и запустите, потом нажмите «Проверить».")
                : t("Не отвечает. Проверьте адрес и ключ, потом нажмите «Проверить».")
        }
    }

    /// Смена провайдера: включаем выбранного и делаем его основным.
    ///
    /// Прежнего не выключаем — он мог быть настроен и пригодиться командам;
    /// «основной» и «включён» здесь разные вещи.
    private func choose(_ provider: AIProvider) {
        settings.setProvider(provider, enabled: true)
        settings.aiProvider = provider
        state.check()
        models.refresh()
    }

    // MARK: - Модели

    /// Карточка одной модели: что она делает, чем сейчас занята и чем её
    /// заменить.
    ///
    /// Две модели рядом — потому что они разного рода, и человеку это
    /// неочевидно: одна отвечает словами, вторая не отвечает вовсе. Подписи
    /// поэтому по делу — «отвечает на вопросы» и «считает смысл», — а не
    /// «модель» и «модель для эмбеддингов».
    private func modelCard(
        title: String,
        symbol: String,
        tint: Color,
        kind: ModelList.Kind,
        recommended: String,
        selection: Binding<String>
    ) -> some View {
        WelcomeCard {
            HStack(spacing: 13) {
                WelcomeGlyph(symbol: symbol, tint: tint, size: WelcomeStyle.tile)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: WelcomeStyle.title, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)

                    if installer.isInstalling(recommended) {
                        HStack(spacing: 8) {
                            ProgressView(value: share).controlSize(.small).frame(width: 120)
                            Text(tf("%d%%", Int(share * 100)))
                                .font(.system(size: WelcomeStyle.detail, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.55))
                        }
                    } else if isInstalled(recommended) {
                        picker(kind: kind, selection: selection)
                    } else {
                        Text(missingText(recommended))
                            .font(.system(size: WelcomeStyle.detail, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)

                // Скачать можно только у Ollama: у прочих провайдеров модели
                // живут на их стороне, и качать со своей нечего.
                if !isInstalled(recommended),
                   !installer.isInstalling(recommended),
                   settings.aiProvider == .ollama {
                    Button(t("Скачать")) { installer.install(recommended) }
                        .buttonStyle(WelcomeGhostButton())
                        .disabled(installer.isBusy)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func missingText(_ recommended: String) -> String {
        settings.aiProvider == .ollama
            ? tf("Нужна модель %@ — около нескольких гигабайт.", recommended)
            : t("Выберите модель своего провайдера в настройках.")
    }

    private func picker(kind: ModelList.Kind, selection: Binding<String>) -> some View {
        let found = models.models(of: settings.aiProvider, kind: kind)
        return Picker("", selection: selection) {
            // Выбранное показываем и тогда, когда список ещё не пришёл:
            // пустое поле читается как «не выбрано», а оно выбрано.
            if !found.contains(where: { $0.name == selection.wrappedValue }) {
                Text(selection.wrappedValue.isEmpty ? t("не выбрана") : selection.wrappedValue)
                    .tag(selection.wrappedValue)
            }
            ForEach(found, id: \.self) { model in
                Text(model.name).tag(model.name)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(maxWidth: 240, alignment: .leading)
    }

    /// Для векторной модели годится **любая** векторная: человек мог скачать
    /// не рекомендованную, а другую, и просить его скачать вторую такую же
    /// незачем.
    private func isInstalled(_ name: String) -> Bool {
        if name == RecommendedModel.embed {
            return !models.models(of: settings.aiProvider, kind: .embedding).isEmpty
        }
        return RecommendedModel.isInstalled(name, among: models.models(of: settings.aiProvider))
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
