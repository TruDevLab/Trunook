import AVFoundation
import AppKit
import SwiftUI

/// Раздел настроек «Команды»: список команд и их правка.
extension SettingsView {
    var commandsSection: some View {
        Group {
            if !settings.ollamaEnabled {
                modelRequiredCard(t("Запросы к модели и разговор работают только с ней."))
            }
            section(t("Команды"), icon: "square.grid.2x2") {
                Toggle(t("Список команд"), isOn: settings.binding(\.quickCommandsEnabled))

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(
                        t("Закрывать панель нажатием мимо неё"),
                        isOn: settings.binding(\.assistantClosesOnClickOutside)
                    )
                    hint(t("Выключено — панель держится, пока её не закрыть крестиком или Esc."))
                }
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(t("Спросить о выделенном"))
                        Spacer()
                        HotKeyRecorder(label: t("Спросить о выделенном"), spec: Binding(
                            get: { settings.assistantHotKey },
                            set: { settings.assistantHotKey = $0; onHotKeysChanged() }
                        ))
                        .frame(width: SettingsStyle.hotKeyField.width,
                                   height: SettingsStyle.hotKeyField.height)
                    }
                    hint(t("Захватывает выделенное и открывает разговор с моделью."))
                }

                // Про подстановку сказано здесь, а не в разделе модели:
                // `{{selection}}` — свойство самой команды, а не модели,
                // и человек ищет его там, где пишет промт.
                hint(t("{{selection}} — место захваченного текста."))
                hint(t("Сочетание команды переезжает вместе с ней, а не остаётся за строкой."))
                hint(t("Модель меняется и в вырезе: Tab или нажатие по её имени в строке."))

                if !settings.ollamaEnabled {
                    // Сказать прямо, а не гасить весь раздел: команды,
                    // которым модель не нужна, работают как работали,
                    // и правят их здесь же.
                    Label(
                        t("Модель выключена — запросы к ней в список не попадают. Остальные команды работают."),
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(Palette.warning)
                }
            }

            ForEach(Array(settings.quickCommands.enumerated()), id: \.element.id) { index, command in
                commandEditor(command, at: index)
            }

            section(t("Ещё команда"), icon: "plus") {
                Button(t("Добавить команду")) { settings.addCommand() }
            }
        }
    }

    /// Одна команда: заголовок с её местом в списке, поля и перестановка.
    ///
    /// Место команды показано номером в заголовке, а меняется перетаскиванием
    /// за ручку в первой строке — см. `dragHandle`.
    func commandEditor(_ command: QuickCommand, at index: Int) -> some View {
        section(tf("%d. %@", index + 1, sectionTitle(for: command)), icon: command.effectiveSymbol) {
            // Всё, что опознаёт команду, — одной строкой: ручка, выключатель,
            // значок, название, клавиша, удаление. Порознь это занимало три
            // строки на карточку, а карточек столько же, сколько команд, —
            // до нижних приходилось прокручивать полэкрана.
            HStack(spacing: SettingsStyle.gap) {
                dragHandle(command)

                // Подпись есть, но скрыта: на экране её заменяет заголовок
                // раздела, а в дереве доступности заменить нечем. С пустой
                // строкой все выключатели команд подряд звучали одинаково —
                // «выключатель», и никак их не различить.
                Toggle(sectionTitle(for: command), isOn: binding(command, \.isEnabled))
                    .labelsHidden()

                symbolButton(command)

                // Подпись скрыта: в узкой строке она встаёт **над** полем
                // и карточка растёт на строку — ровно то, от чего уходили.
                // Приглашение внутри поля говорит то же самое, а диктору
                // остаётся имя.
                TextField(text: binding(command, \.title), prompt: Text(t("Название"))) {
                    Text(t("Название"))
                }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)

                HotKeyRecorder(
                    label: tf("Сочетание команды «%@»", sectionTitle(for: command)),
                    spec: Binding(
                        get: { settings.quickCommands.first { $0.id == command.id }?.hotKey },
                        set: { spec in
                            guard var updated = settings.quickCommands.first(where: { $0.id == command.id })
                            else { return }
                            updated.hotKey = spec
                            settings.updateCommand(updated)
                            onHotKeysChanged()
                        }
                    ),
                    placeholder: t("Без клавиши")
                )
                .frame(width: SettingsStyle.hotKeyFieldNarrow.width,
                       height: SettingsStyle.hotKeyFieldNarrow.height)

                Button {
                    settings.removeCommand(id: command.id)
                    // Сочетание уходит вместе с командой: оставленное
                    // зарегистрированным, оно молча срабатывало бы в пустоту
                    // до следующего перезапуска.
                    onHotKeysChanged()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help(t("Удалить команду"))
                .accessibilityLabel(tf("Удалить команду «%@»", sectionTitle(for: command)))
            }

            // Действие и модель — в одну строку: обе отвечают на «чем это
            // выполнить», и стоять им порознь незачем.
            HStack(spacing: 12) {
                Picker(t("Действие"), selection: binding(command, \.kind)) {
                    ForEach(QuickCommand.Kind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.menu)

                if command.kind.usesModel { modelPicker(command) }
            }

            payloadEditor(command)
        }
        // Приглушённая карточка — та же мысль, что и предупреждение выше,
        // но у конкретной команды: эта в список сейчас не попадает.
        // Не `disabled`: править её никто не запрещал, а починить настройку
        // из погашенного поля было бы нечем.
        .opacity(command.kind.usesModel && !settings.ollamaEnabled ? 0.55 : 1)
    }

    /// Название раздела команды.
    ///
    /// У новой команды названия ещё нет, а заголовок «2.» без ничего не даёт
    /// понять, что это за раздел и почему он пуст.
    func sectionTitle(for command: QuickCommand) -> String {
        command.title.isEmpty ? t("Новая команда") : command.title
    }

    /// Ручка перетаскивания — значок в начале первой строки карточки.
    ///
    /// Перетаскивание вместо кнопок «выше» и «ниже»: кнопками порядок из семи
    /// команд меняется десятком нажатий, и после каждого список
    /// перерисовывается — ту же карточку приходится искать глазами заново.
    ///
    /// Ручкой, а не всей карточкой: раздел собран из `Section` внутри `Form`,
    /// а модификатор, повешенный на `Section`, достаётся **каждой её строке**
    /// порознь. Перетаскивалось бы тогда поле промта, переключатель и выбор
    /// модели — по отдельности и каждое само по себе.
    ///
    /// Переносится строка с номером, а не сама команда: `Transferable`
    /// у `QuickCommand` означал бы, что её можно вытащить наружу приложения,
    /// где она никому не нужна и ничего не значит.
    func dragHandle(_ command: QuickCommand) -> some View {
        let isTarget = selection.commandDropTarget == command.id
        return Image(systemName: "line.3.horizontal")
            .foregroundStyle(isTarget ? Color.accentColor : .secondary)
            .frame(width: 18, height: 22)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isTarget ? Color.accentColor.opacity(0.18) : .clear)
            )
            .draggable(String(command.id)) {
                Label(sectionTitle(for: command), systemImage: command.effectiveSymbol)
                    .padding(6)
            }
            .dropDestination(for: String.self) { items, _ in
                selection.commandDropTarget = nil
                guard let raw = items.first, let moved = Int(raw) else { return false }
                settings.moveCommand(id: moved, onto: command.id)
                return true
            } isTargeted: { targeted in
                // Своё — только своё: курсор уже мог перейти на соседнюю
                // карточку, и та успела записаться раньше, чем эта сообщила
                // об уходе.
                if targeted {
                    selection.commandDropTarget = command.id
                } else if selection.commandDropTarget == command.id {
                    selection.commandDropTarget = nil
                }
            }
            .animation(.easeOut(duration: 0.12), value: isTarget)
            .help(t("Перетащите, чтобы поменять порядок"))
            .accessibilityLabel(tf("Переставить команду «%@»", sectionTitle(for: command)))
    }

    /// Значок команды — тот, что стоит в её строке под чёлкой.
    ///
    /// Кнопкой с текущим значком, а не разложенной палитрой: тридцать шесть
    /// значков занимали в карточке шесть строк — больше, чем всё остальное
    /// вместе взятое, — и это в разделе, где карточек столько же, сколько
    /// команд. Выбирают значок один раз, а прокручивают мимо него каждый раз.
    ///
    /// Палитрой, а не полем для имени символа: имя пришлось бы знать наизусть
    /// («text.badge.checkmark»), опечатка в нём давала бы пустое место
    /// в строке под чёлкой, а свериться было бы негде — приложение SF Symbols
    /// ставится вместе с Xcode, которого на этой машине нет.
    func symbolButton(_ command: QuickCommand) -> some View {
        Button {
            selection.symbolPickerFor = command.id
        } label: {
            Image(systemName: command.effectiveSymbol)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .help(t("Значок"))
        .accessibilityLabel(t("Значок"))
        .popover(
            isPresented: Binding(
                get: { selection.symbolPickerFor == command.id },
                set: { shown in
                    if !shown, selection.symbolPickerFor == command.id {
                        selection.symbolPickerFor = nil
                    }
                }
            ),
            arrowEdge: .bottom
        ) {
            symbolGrid(command)
        }
    }

    func symbolGrid(_ command: QuickCommand) -> some View {
        VStack(alignment: .leading, spacing: SettingsStyle.gap) {
            Text(t("Значок"))
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 34), spacing: 6)],
                spacing: 6
            ) {
                symbolChoice(command, symbol: "", isDefault: true)
                ForEach(CommandSymbols.all, id: \.self) { symbol in
                    symbolChoice(command, symbol: symbol, isDefault: false)
                }
            }
            .frame(width: 280)

            Text(t("Первый — как у действия: меняется вместе с ним."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(12)
    }

    func symbolChoice(
        _ command: QuickCommand,
        symbol: String,
        isDefault: Bool
    ) -> some View {
        let isOn = command.symbol == symbol
        let shown = isDefault ? command.kind.defaultSymbol : symbol
        return Button {
            guard var updated = settings.quickCommands.first(where: { $0.id == command.id })
            else { return }
            updated.symbol = symbol
            settings.updateCommand(updated)
            selection.symbolPickerFor = nil
        } label: {
            Image(systemName: shown)
                .font(.system(size: 14))
                .frame(width: 30, height: 26)
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isOn ? Color.accentColor : Color.primary.opacity(0.08))
                )
                .overlay(
                    // Пунктиром — «как у действия»: он не выбран из палитры,
                    // а взят у вида, и рисовать его наравне с остальными
                    // значило бы прятать разницу.
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(
                            Color.primary.opacity(isDefault && !isOn ? 0.25 : 0),
                            style: StrokeStyle(lineWidth: 1, dash: [3, 2])
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        // Имя постоянное, состояние отдельным значением: меняющееся имя
        // диктор прочтёт как другую кнопку.
        .accessibilityLabel(isDefault ? t("Как у действия") : shown)
        .accessibilityValue(isOn ? t("выбрано") : "")
        .help(isDefault ? t("Как у действия") : shown)
    }

    /// Какой моделью выполнять эту команду.
    ///
    /// Отдельно от общей модели в разделе «Модель»: там задают ту, которой
    /// отвечают все, здесь — исключение для одной команды. «Как в настройках»
    /// первым пунктом и есть отсутствие исключения.
    func modelPicker(_ command: QuickCommand) -> some View {
        // Без пояснения рядом: оно одно и то же у всех команд, а места
        // в строке отнимало столько, что оба выпадающих списка сжимались
        // до «Запрос к м…» и «Как в настро…». Сказано один раз, сверху.
        Picker(t("Модель"), selection: Binding(
            get: { settings.quickCommands.first { $0.id == command.id }?.model ?? "" },
            set: { name in
                guard var updated = settings.quickCommands.first(where: { $0.id == command.id })
                else { return }
                updated.model = name.isEmpty ? nil : name
                settings.updateCommand(updated)
            }
        )) {
            Text(tf("Как в настройках (%@)", settings.defaultModel.shortName)).tag("")
            // Выбранная когда-то модель могла исчезнуть с сервера — или
            // сам сервер выключили. Без этого пункта список показал бы
            // пустую строку, и было бы неясно, что вообще выбрано.
            if let stored = command.model, !known.contains(stored) {
                Text(tf("%@ — не найдена", stored)).tag(stored)
            }
            ForEach(models.models, id: \.self) { model in
                // Марка провайдера и его имя: в окне настроек места хватает
                // обоим, а одно и то же имя модели бывает у двух серверов
                // сразу — выбор из двух одинаковых строк не выбор.
                Label {
                    Text(CommandRows.full(model))
                } icon: {
                    ProviderIcon(provider: model.provider, size: SettingsStyle.font(13))
                }
                .tag(model.stored)
            }
        }
        .pickerStyle(.menu)
    }

    /// Сохранённые имена моделей — чтобы отличить исчезнувшую от найденной.
    var known: Set<String> { Set(models.models.map(\.stored)) }

    /// Поле значения зависит от типа: путь выбирается диалогом, готовое
    /// действие — списком, и только промт и свой скрипт пишутся руками.
    @ViewBuilder
    func payloadEditor(_ command: QuickCommand) -> some View {
        switch command.kind {
        case .saveToNotes:
            // Заполнять нечего: команда работает с захваченным текстом,
            // а не со своим содержимым. Пустое поле здесь предлагало бы
            // вписать то, чего у неё нет.
            hint(t("Кладёт захваченный текст заметкой, без модели."))

        case .shortcut:
            if ShortcutsService.isAvailable {
                HStack {
                    Picker(t("Команда"), selection: Binding(
                        get: {
                            settings.quickCommands.first { $0.id == command.id }?.payload ?? ""
                        },
                        set: { name in
                            applyChoice(to: command, payload: name, title: name)
                        }
                    )) {
                        if command.payload.isEmpty {
                            Text(t("Не выбрана")).tag("")
                        }
                        ForEach(shortcuts.names, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.menu)

                    Button {
                        shortcuts.refresh()
                    } label: {
                        if shortcuts.isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(shortcuts.isLoading)
                    .help(t("Обновить список команд"))
                    .accessibilityLabel(t("Обновить список команд"))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Передавать выделенный текст"), isOn: binding(command, \.passesSelection))
                    hint(t("Если команда что-то возвращает, результат попадёт в буфер обмена."))
                }
                .accessibilityElement(children: .combine)
            } else {
                Text(t("Приложение «Команды» недоступно"))
                    .font(.callout)
                    .foregroundStyle(Palette.warning)
            }

        case .ollama:
            // Именно TextEditor, а не TextField: у поля ввода Return отправляет
            // форму, а не переносит строку, и промт нельзя было разбить
            // на абзацы — а промты пишут абзацами.
            multilineEditor(
                text: binding(command, \.payload),
                placeholder: t("Переведи на английский.\n\n{{selection}}"),
                minHeight: 76
            )

        case .openApp:
            pathRow(command, chooser: CommandPickers.chooseApplication, empty: t("Приложение не выбрано"))

        case .openPath:
            pathRow(command, chooser: CommandPickers.choosePath, empty: t("Путь не выбран"))

        case .openURL:
            TextField("https://example.com", text: binding(command, \.payload))

            Picker(t("Браузер"), selection: Binding(
                get: {
                    settings.quickCommands.first { $0.id == command.id }?.browserBundleID ?? ""
                },
                set: { bundleID in
                    guard var updated = settings.quickCommands.first(where: { $0.id == command.id })
                    else { return }
                    updated.browserBundleID = bundleID.isEmpty ? nil : bundleID
                    settings.updateCommand(updated)
                }
            )) {
                Text(browsers.defaultName.map { tf("По умолчанию — %@", $0) } ?? t("Браузер по умолчанию"))
                    .tag("")
                ForEach(browsers.items) { browser in
                    Text(browser.name).tag(browser.bundleID)
                }
                // Выбранный когда-то браузер мог исчезнуть из системы.
                // Без этого пункта список показал бы пустую строку, и было
                // бы неясно, что вообще выбрано.
                if let bundleID = command.browserBundleID,
                   !bundleID.isEmpty,
                   browsers.name(forBundleID: bundleID) == nil {
                    Text(tf("%@ — не найден", bundleID)).tag(bundleID)
                }
            }
            .pickerStyle(.menu)

            hint(t("Схему можно не писать: «ya.ru» откроется как «https://ya.ru»."))

        case .appleScript:
            Picker(t("Действие"), selection: Binding(
                get: { ScriptPreset.matching(command.payload)?.id ?? "custom" },
                set: { id in
                    guard let preset = ScriptPreset.all.first(where: { $0.id == id }) else {
                        // «Свой скрипт»: очищаем текст, название не трогаем.
                        guard var updated = settings.quickCommands.first(where: { $0.id == command.id })
                        else { return }
                        updated.payload = ""
                        settings.updateCommand(updated)
                        return
                    }
                    applyChoice(
                        to: command,
                        payload: preset.source,
                        title: preset.title,
                        symbol: preset.symbol
                    )
                }
            )) {
                ForEach(ScriptPreset.all) { preset in
                    Text(preset.title).tag(preset.id)
                }
                Text(t("Свой скрипт")).tag("custom")
            }
            .pickerStyle(.menu)

            if ScriptPreset.matching(command.payload) == nil {
                multilineEditor(
                    text: binding(command, \.payload),
                    placeholder: "tell application \"Finder\" to activate",
                    minHeight: 84,
                    isCode: true
                )
            }
        }
    }

    /// Записывает новый выбор в слот, подставляя название и значок.
    ///
    /// Название подставляется, только если пользователь его не менял сам.
    /// Признак этого — совпадение с тем, что подставилось бы для прежнего
    /// выбора: раньше проверялось лишь «поле пустое», и смена приложения
    /// оставляла подпись от предыдущего.
    func applyChoice(
        to command: QuickCommand,
        payload: String,
        title: String,
        symbol: String? = nil
    ) {
        guard var updated = settings.quickCommands.first(where: { $0.id == command.id })
        else { return }

        let previousTitle = Self.autoTitle(for: updated)
        let previousSymbol = Self.autoSymbol(for: updated)

        if updated.title.isEmpty || updated.title == previousTitle {
            updated.title = title
        }
        if let symbol, updated.symbol.isEmpty || updated.symbol == previousSymbol {
            updated.symbol = symbol
        }
        updated.payload = payload
        settings.updateCommand(updated)
    }

    /// Какое название подставилось бы для нынешнего содержимого слота.
    static func autoTitle(for command: QuickCommand) -> String {
        switch command.kind {
        case .openApp:
            return (command.payload as NSString).lastPathComponent
                .replacingOccurrences(of: ".app", with: "")
        case .openPath:
            return (command.payload as NSString).lastPathComponent
        case .shortcut:
            return command.payload
        case .appleScript:
            return ScriptPreset.matching(command.payload)?.title ?? ""
        case .saveToNotes:
            return QuickCommand.Kind.saveToNotes.title
        case .openURL, .ollama:
            // Название здесь не угадать: адрес набирают по буквам, и любой
            // догадке пришлось бы меняться на каждом нажатии клавиши.
            return ""
        }
    }

    static func autoSymbol(for command: QuickCommand) -> String? {
        guard command.kind == .appleScript else { return nil }
        return ScriptPreset.matching(command.payload)?.symbol
    }

    func pathRow(
        _ command: QuickCommand,
        chooser: @escaping () -> (path: String, name: String)?,
        empty: String
    ) -> some View {
        HStack(spacing: 10) {
            if let icon = CommandPickers.icon(forPath: command.payload) {
                Image(nsImage: icon).resizable().frame(width: SettingsStyle.scaled(20), height: SettingsStyle.scaled(20))
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .foregroundStyle(.secondary)
                    .frame(width: SettingsStyle.scaled(20), height: SettingsStyle.scaled(20))
            }

            Text(command.payload.isEmpty ? empty : (command.payload as NSString).lastPathComponent)
                .font(.system(size: SettingsStyle.font(12)))
                .foregroundStyle(command.payload.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            Button(t("Выбрать…")) {
                guard let picked = chooser() else { return }
                applyChoice(to: command, payload: picked.path, title: picked.name)
            }
        }
    }

    /// Правка одного поля слота. Слоты хранятся набором, поэтому связывание
    /// идёт через поиск по идентификатору, а не по индексу: индекс сместился
    /// бы при любой перестановке.
    func binding<Value>(
        _ command: QuickCommand,
        _ keyPath: WritableKeyPath<QuickCommand, Value>
    ) -> Binding<Value> {
        Binding(
            get: {
                settings.quickCommands.first { $0.id == command.id }?[keyPath: keyPath]
                    ?? command[keyPath: keyPath]
            },
            set: { newValue in
                guard var updated = settings.quickCommands.first(where: { $0.id == command.id })
                else { return }
                updated[keyPath: keyPath] = newValue
                settings.updateCommand(updated)
            }
        )
    }
}
