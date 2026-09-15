import AVFoundation
import AppKit
import SwiftUI

/// Раздел настроек «ИИ»: модель, движок, каталог, помощник, провайдеры.
extension SettingsView {
    /// Настройки модели — своим разделом, а не внутри команд.
    ///
    /// Внутри команд они и лежали, пока модель была нужна только им. Теперь
    /// на ней держатся ещё и заметки: имя записи, поиск по всему архиву,
    /// разговор в панели. Настройка, спрятанная в разделе одной из функций,
    /// выглядит её частью — и человек, у которого не работают заметки, ищет
    /// причину где угодно, кроме раздела «Команды».
    /// Кто отвечает: основной провайдер среди включённых.
    ///
    /// Основной отвечает на свободный вопрос и на команды, у которых своей
    /// модели нет. Выбирается он **только среди включённых**: назначить
    /// основным выключенного значило бы отправлять вопрос туда, где его
    /// никто не ждёт, и понять это по экрану было бы нельзя.
    var providerPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(t("Основной"), selection: Binding(
                get: { settings.aiProvider },
                set: { settings.aiProvider = $0; models.refresh() }
            )) {
                ForEach(settings.enabledProviders) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .pickerStyle(.menu)

            hint(t("Ему уходят свободный вопрос и команды без своей модели."))
        }
        .accessibilityElement(children: .combine)
    }

    /// Настройки одного провайдера: адрес, ключ, модель.
    ///
    /// Своим разделом на каждого, а не общими полями на всех. Общими они были
    /// ровно одну версию, и этого хватило: ключ от прежнего провайдера
    /// оставался в поле нового, уходил с запросом и получал отказ, в котором
    /// виноватым выглядел новый сервер.
    func providerSection(_ provider: AIProvider) -> some View {
        // Заголовок — маркой самого провайдера, той же, что стоит в строке
        // команды. Две разные картинки на одного означали бы, что связать
        // раздел настроек со строкой в вырезе можно только по названию.
        section(provider.title, mark: provider) {
            if provider.isRemote {
                // Сказано прямо и с предупреждающим знаком: это единственное
                // место в приложении, где вопрос и захваченный текст уходят
                // с машины. Промолчать об этом было бы обманом умолчанием.
                Label(
                    t("Вопросы и захваченный текст уходят в интернет этому сервису."),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout)
                .foregroundStyle(Palette.warning)
            }

            field(
                t("Адрес"),
                prompt: provider == .ollama
                    ? Settings.defaultOllamaURL
                    : (provider.presetURL ?? "https://…/v1"),
                text: Binding(
                    get: { settings.apiURLRaw(for: provider) },
                    set: { settings.setAPIURL($0, for: provider) }
                )
            )

            if provider.usesKey {
                VStack(alignment: .leading, spacing: 4) {
                    field(
                        t("Ключ доступа"),
                        prompt: "sk-…",
                        text: Binding(
                            get: { settings.apiKey(for: provider) },
                            set: { settings.setAPIKey($0, for: provider) }
                        ),
                        isSecret: true
                    )
                    hint(t("Хранится в настройках приложения, не в связке ключей."))
                }
            }

            providerModelPicker(provider)

            // Удержание модели в памяти — свойство Ollama, а не разговора:
            // у прочих этим распоряжается сервер, и настройка, показанная
            // рядом, обещала бы влияние, которого у неё нет.
            // Пустой список моделей у свежепоставленной Ollama — обычное
            // дело: сервер есть, моделей в нём нет. Раньше это был тупик
            // с уходом в терминал; теперь рядом кнопка.
            if provider == .ollama {
                installRow(RecommendedModel.chat)
            }

            if provider == .ollama {
                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Держать модель в памяти"), selection: settings.binding(\.ollamaKeepAlive)) {
                        Text(t("5 минут")).tag("5m")
                        Text(t("30 минут")).tag("30m")
                        Text(t("2 часа")).tag("2h")
                        Text(t("Постоянно")).tag("-1")
                    }
                    .pickerStyle(.menu)

                    hint(t("Первый запрос после простоя ждёт загрузки модели — около минуты."))
                }
                .accessibilityElement(children: .combine)
            }

            // Основного не убрать: без него запрос уходить некуда. Кнопка
            // остаётся видимой и погашенной — исчезнувшая читалась бы как
            // «этого провайдера убрать нельзя вообще», хотя достаточно
            // назначить основным другого.
            HStack {
                Spacer()
                Button(t("Убрать провайдера"), role: .destructive) {
                    settings.setProvider(provider, enabled: false)
                    models.refresh()
                }
                .disabled(provider == settings.aiProvider)
            }
        }
    }

    func providerModelPicker(_ provider: AIProvider) -> some View {
        // Векторные модели сюда не попадают: они не отвечают словами вовсе,
        // и выбранная по ошибке молчала бы на каждый вопрос.
        let found = models.models(of: provider, kind: .chat)
        let current = settings.apiModel(for: provider)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Picker(t("Модель"), selection: Binding(
                    get: { current },
                    set: { settings.setAPIModel($0, for: provider) }
                )) {
                    // Выбранное показываем, даже когда список не пришёл:
                    // иначе поле выглядит пустым, будто модель не выбрана
                    // вовсе, — а она выбрана, просто сервер сейчас молчит.
                    if !found.contains(where: { $0.name == current }) {
                        Text(current.isEmpty ? t("не выбрана") : current).tag(current)
                    }
                    ForEach(found, id: \.self) { model in
                        // Имя провайдера здесь не нужно: раздел уже его,
                        // и повторять было бы шумом. Марка остаётся —
                        // по ней строка узнаётся боковым зрением.
                        Label {
                            Text(model.name)
                        } icon: {
                            ProviderIcon(provider: provider, size: SettingsStyle.font(13))
                        }
                        .tag(model.name)
                    }
                }
                .pickerStyle(.menu)

                Button {
                    models.refresh()
                } label: {
                    if models.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(models.isLoading)
                // Имя рядом с подсказкой, а не вместо неё: `.help` в macOS
                // кладёт текст в подсказку элемента, а имя оставляет пустым —
                // кнопка из одного значка так и остаётся для диктора
                // безымянной.
                .help(t("Обновить список моделей"))
                .accessibilityLabel(t("Обновить список моделей"))
            }
        }
    }

    /// Чего ещё нет в списке.
    ///
    /// Меню, а не длинный список переключателей: провайдеров дюжина,
    /// а держат обычно один-два, и одиннадцать выключенных строк заняли бы
    /// весь раздел, ничего о себе не сообщая.
    var addProviderMenu: some View {
        let rest = AIProvider.allCases.filter { !settings.isProviderEnabled($0) }
        return Menu(t("Добавить провайдера")) {
            Section(t("На этом компьютере")) {
                ForEach(rest.filter(\.isLocal)) { provider in
                    Button(provider.title) { add(provider) }
                }
            }
            Section(t("В интернете")) {
                ForEach(rest.filter { $0.isRemote }) { provider in
                    Button(provider.title) { add(provider) }
                }
            }
            if rest.contains(.custom) {
                Section {
                    Button(AIProvider.custom.title) { add(.custom) }
                }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(rest.isEmpty)
    }

    func add(_ provider: AIProvider) {
        settings.setProvider(provider, enabled: true)
        // Список моделей перечитывается сразу: у нового провайдера он свой,
        // и без запроса его модели не появятся в выборе ни у одной команды.
        models.refresh()
    }

    /// Поле ввода с подписью над ним.
    ///
    /// Подпись сверху, а не слева, и рамка обязательна. Без рамки поле
    /// не видно вовсе: `Form` рисует значение простым текстом у правого края,
    /// и пустое поле выглядит просто отсутствующим — строка «Ключ доступа»
    /// стояла с пустотой справа, и вписать в неё что-либо человек
    /// не догадывался. Длинная подпись вдобавок переносилась на две строки
    /// и отжимала поле к краю.
    func field(
        _ title: String,
        prompt: String,
        text: Binding<String>,
        isSecret: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout)
                .foregroundStyle(SettingsStyle.secondary)

            Group {
                if isSecret {
                    SecureField(title, text: text, prompt: Text(prompt))
                } else {
                    TextField(title, text: text, prompt: Text(prompt))
                }
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: SettingsStyle.pickerWidth)
        }
    }

    /// Настройки модели — своим разделом, а не внутри команд.
    ///
    /// Внутри команд они и лежали, пока модель была нужна только им. Теперь
    /// на ней держатся ещё и заметки: имя записи, поиск по всему архиву,
    /// разговор в панели. Настройка, спрятанная в разделе одной из функций,
    /// выглядит её частью — и человек, у которого не работают заметки, ищет
    /// причину где угодно, кроме раздела «Команды».
    /// Помощник, который делает.
    ///
    /// В разделе «Модель», а не «Инструменты»: тот занят буфером, полкой
    /// и таймером — вещами системы, — а помощник целиком про модель. Он
    /// живёт её умением звать инструменты и гаснет вместе с ней, и
    /// предупреждение «эта модель так не умеет» ничего не стоит вдали
    /// от выбора модели, к которому относится.
    var agentCard: some View {
        section(t("Помощник с действиями"), icon: "wand.and.stars") {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(t("Помощник может действовать"), isOn: settings.binding(\.agentEnabled))
                hint(t("Ставит таймер, смотрит календарь и погоду; запись спрашивает подтверждением."))
            }
            .accessibilityElement(children: .combine)

            if settings.agentEnabled {
                toolSupportNote
                ForEach(AgentTool.allCases) { tool in agentToolRow(tool) }
            }
        }
    }

    /// Умеет ли выбранная модель звать инструменты.
    ///
    /// Про `defaultModel`: свободный вопрос уходит именно ему. У команды
    /// бывает своя модель, но команды помощником не становятся.
    @ViewBuilder
    var toolSupportNote: some View {
        let model = settings.defaultModel
        switch models.toolSupport(of: model) {
        case .yes:
            hint(tf("Модель %@ умеет вызывать инструменты.", model.shortName))
        case .no:
            Text(tf("Модель %@ не умеет вызывать инструменты — действовать помощник с ней не сможет. Выберите другую.", model.shortName))
                .font(.callout)
                .foregroundStyle(Palette.warning)
        case .unknown:
            hint(t("Умеет ли эта модель вызывать инструменты, сервер не сообщает. Если действия не срабатывают — дело в модели, а не в настройке."))
        }
    }

    /// Строка инструмента: что помощник умеет прямо сейчас и почему нет.
    ///
    /// Своих переключателей у инструментов нет: каждый жив ровно пока
    /// включена его функция. Но исчезать строка не должна — исчезнувшая
    /// читается как «этого не бывает вовсе», а погасшая с причиной учит,
    /// куда пойти и что включить.
    func agentToolRow(_ tool: AgentTool) -> some View {
        let reason = tool.blockedReason(settings)
        return HStack(spacing: SettingsStyle.gap) {
            Image(systemName: reason == nil ? "checkmark.circle.fill" : "circle.slash")
                .foregroundStyle(reason == nil ? SettingsStyle.accent : .secondary)
                .symbolSwap(reason == nil)
            Text(tool.title)
                .foregroundStyle(reason == nil ? .primary : .secondary)
            Spacer()
            if let reason {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if tool.needsConfirmation {
                Text(t("с подтверждением"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var modelSection: some View {
        Group {
            section(t("Запросы к модели"), icon: "sparkles") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Модель"), isOn: settings.binding(\.ollamaEnabled))
                    hint(t("Нужна командам, разговору и заметкам."))
                }
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Отвечать без раздумий"), isOn: settings.binding(\.fastAnswers))
                    hint(t("Быстрее в разы, но некоторые модели начинают рассуждать прямо в ответе."))
                }
                .accessibilityElement(children: .combine)
                .disabled(!settings.ollamaEnabled)

                if let error = models.error, settings.ollamaEnabled {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(Palette.warning)
                }
            }

            // Карточки видны и при выключенной модели — серыми: скрытые, они
            // не давали понять, что раздел вообще умеет. Прячется только то,
            // чего у выбранного провайдера нет вовсе.
            Group {
                if settings.aiProvider == .ollama { engineSection }
                if settings.aiProvider == .ollama { catalogueSection }
                agentCard
                advancedSection
            }
            .disabled(!settings.ollamaEnabled)
        }
    }

    /// Сам движок: стоит ли, работает ли, и одна кнопка по делу.
    ///
    /// Рисуется только у местного провайдера: у облачного движка нет вовсе,
    /// и предлагать там установку было бы бессмыслицей.
    var engineSection: some View {
        section(t("Движок моделей"), icon: "shippingbox.fill") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: SettingsStyle.gap) {
                    if case let .downloading(share) = engine.state {
                        ProgressView(value: share).controlSize(.small).frame(width: 90)
                    }
                    Text(engine.line.text)
                        .font(.system(size: SettingsStyle.font(12.5)))
                    Spacer(minLength: 8)
                    engineButton
                }
                // Сказать прямо: Ollama — чужая программа, она останется
                // на машине и будет видна в строке меню. Прятать это
                // значило бы поставить её втихую.
                hint(t("Ollama — бесплатная программа с открытым кодом. Она запускает модели на этом компьютере и остаётся в строке меню."))
                if settings.didInstallOllamaApp {
                    hint(t("Её поставил Trunook. Удаляется как обычная программа, из папки «Программы»."))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle(t("Запускать Ollama вместе с Trunook"), isOn: settings.binding(\.ollamaAutoStart))
                hint(t("Иначе первый вопрос дня не дойдёт до модели."))
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    var engineButton: some View {
        switch engine.line.action {
        case .none, .busy:
            EmptyView()
        case .install:
            Button(t("Установить Ollama")) { engine.install() }
        case .start:
            Button(t("Запустить")) { engine.start() }
        case .check:
            Button(t("Проверить")) { engine.refresh() }
        case .cancel:
            Button(t("Отменить")) { engine.cancelInstall() }
        case .reveal:
            Button(t("Показать в Finder")) { engine.revealImage() }
        case .copyCommand:
            Button(t("Скопировать команду")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(OllamaApp.serveCommand, forType: .string)
            }
        }
    }

    /// Что скачать: три разряда по ресурсам машины и модель для заметок.
    var catalogueSection: some View {
        section(t("Модели"), icon: "square.and.arrow.down") {
            ModelOfferRows(
                rows: ModelCatalogue.rows(
                    on: MachineResources.current(),
                    installed: models.models(of: .ollama),
                    selected: settings.apiModel(for: .ollama),
                    installing: installer.installing,
                    share: installedShare,
                    queued: installer.waiting
                ),
                onInstall: { tag in
                    installer.enqueue([tag])
                    // Скачанное надо сделать тем, чем отвечают: иначе
                    // человек качает одно, а приложение просит другое,
                    // и первый же вопрос падает «модели нет».
                    settings.setAPIModel(tag, for: .ollama)
                },
                onSelect: { tag in settings.setAPIModel(tag, for: .ollama) }
            )

            if let pair = pairToInstall {
                VStack(alignment: .leading, spacing: 4) {
                    Button(t("Установить рекомендованное")) {
                        installer.enqueue(pair)
                        if let chat = pair.first { settings.setAPIModel(chat, for: .ollama) }
                    }
                    .disabled(!engine.state.isRunning)
                    hint(t("Модель для разговора и модель для заметок — подряд, одной кнопкой."))
                }
            }

            if case let .failed(text) = installer.state {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(Palette.warning)
            }
        }
    }

    /// Что осталось поставить из рекомендованного. `nil` — всё уже стоит,
    /// и кнопка была бы предложением сделать сделанное.
    var pairToInstall: [String]? {
        let pair = ModelCatalogue.recommendedPair(on: MachineResources.current())
        let installed = models.models(of: .ollama)
        let left = pair.filter { !RecommendedModel.isInstalled($0, among: installed) }
        return left.isEmpty ? nil : pair
    }

    /// Адреса, ключи и двенадцать провайдеров — для тех, у кого свой сервер
    /// или облачный ключ.
    ///
    /// Свёрнуто: человеку, которому всё это не нужно, оно мешало, стоя
    /// первым на экране. Но у того, кто ключ уже прописал, раздел раскрыт
    /// с самого начала — свёрнутый читался бы как «ключ пропал после
    /// обновления».
    ///
    /// `DisclosureGroup` не используется: в проекте его нет ни разу,
    /// а модификаторы `Section` здесь ложатся на каждую строку отдельно.
    var advancedSection: some View {
        Group {
            section(t("Дополнительно"), icon: "slider.horizontal.3") {
                Button {
                    selection.showsAdvancedProviders.toggle()
                    settings.showsAdvancedProviders = selection.showsAdvancedProviders
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: SettingsStyle.font(10), weight: .semibold))
                            .disclosureTurn(selection.showsAdvancedProviders)
                        Text(t("Свой сервер или облачный ключ"))
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)

                if selection.showsAdvancedProviders, settings.enabledProviders.count > 1 {
                    providerPicker
                }
            }

            if selection.showsAdvancedProviders {
                ForEach(settings.enabledProviders) { provider in
                    providerSection(provider)
                }

                section(t("Ещё провайдер"), icon: "plus") {
                    addProviderMenu
                }
            }
        }
    }
}
