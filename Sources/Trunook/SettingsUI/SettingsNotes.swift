import AVFoundation
import AppKit
import SwiftUI

/// Раздел настроек «Заметки»: заметки, запись разговора, связи и Obsidian.
extension SettingsView {
    var notesSection: some View {
        Group {
            section(t("Заметки"), icon: "list.bullet.rectangle") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Заметки"), isOn: Binding(
                        get: { settings.notesEnabled },
                        set: { settings.notesEnabled = $0; onHotKeysChanged() }
                    ))
                    hint(t("Живут в панели модели. Работают и с выключенной Ollama."))
                }
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(t("Новая заметка"))
                        Spacer()
                        HotKeyRecorder(label: t("Новая заметка"), spec: Binding(
                            get: { settings.notesHotKey },
                            set: { settings.notesHotKey = $0; onHotKeysChanged() }
                        ))
                        .frame(width: SettingsStyle.hotKeyField.width,
                               height: SettingsStyle.hotKeyField.height)
                    }
                    .disabled(!settings.notesEnabled)
                    hint(t("Открывает пустую заметку. Список — кнопкой в той же панели."))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(t("Выделенное в заметки"))
                        Spacer()
                        HotKeyRecorder(label: t("Выделенное в заметки"), spec: Binding(
                            get: { settings.noteSelectionHotKey },
                            set: { settings.noteSelectionHotKey = $0; onHotKeysChanged() }
                        ))
                        .frame(width: SettingsStyle.hotKeyField.width,
                               height: SettingsStyle.hotKeyField.height)
                    }
                    .disabled(!settings.notesEnabled)
                    hint(t("Записывает выделенный текст, ничего не открывая."))
                    hint(t("Нужен Универсальный доступ."))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(t("Скопированное в заметки"))
                    hint(t("Кнопка есть в истории буфера и на плашке о копировании."))
                    hint(t("Только для текста."))
                }
                .disabled(!settings.notesEnabled || !settings.clipboardEnabled)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Имя заметке придумывает модель"), isOn: settings.binding(\.notesTitleByModel))
                        .disabled(!settings.ollamaEnabled)
                        .disabled(!settings.notesEnabled || !settings.ollamaEnabled)
                    hint(t("Сразу ставится из даты и первой строки, потом модель уточняет."))
                }
                .accessibilityElement(children: .combine)

                recordCard

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Искать по смыслу"), isOn: Binding(
                        get: { settings.notesVectorSearch },
                        set: { settings.notesVectorSearch = $0; linker.refreshAll() }
                    ))
                    hint(t("Модели уходят только подходящие заметки, а не все подряд."))
                }
                .accessibilityElement(children: .combine)
                .disabled(!settings.notesEnabled || !settings.ollamaEnabled)

                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Заметок под вопрос"), selection: settings.binding(\.notesVectorCount)) {
                        ForEach([4, 6, 10, 15, 20], id: \.self) { value in
                            Text(tf("%d", value)).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    hint(t("Сколько подходящих заметок отдавать модели."))
                }
                .accessibilityElement(children: .combine)
                .disabled(!settings.notesEnabled || !settings.ollamaEnabled || !settings.notesVectorSearch)

            }

            section(t("Что с ними делать"), icon: "square.and.arrow.up") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(tf("Заметок сейчас: %d", notes.total))
                        Spacer()
                        Button(t("Очистить все"), role: .destructive, action: clearNotes)
                            .disabled(notes.total == 0)
                    }
                    hint(tf("Хранятся в %@. Выгрузка в Markdown — кнопкой в самом списке заметок.", NotesStore.defaultURL.path))
                }
            }

            obsidianSection
            linksSection
        }
    }

    /// Карточка связей.
    ///
    /// Связи ищут векторами: совпадение слов на вопрос «о том же ли» не
    /// отвечает. Запись в файлы — отдельным переключателем: одно дело
    /// показать связи, другое — писать в личные файлы человека.
    var linksSection: some View {
        section(t("Связи между заметками"), icon: "point.3.filled.connected.trianglepath.dotted") {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(t("Искать связи"), isOn: Binding(
                    get: { settings.obsidianLinksEnabled },
                    set: { settings.obsidianLinksEnabled = $0; linksChanged() }
                ))
                hint(t("Модель находит заметки об одном и том же, даже когда общих слов в них нет."))
            }
            .accessibilityElement(children: .combine)
            .disabled(!settings.ollamaEnabled)

            VStack(alignment: .leading, spacing: 4) {
                embedModelPicker
                hint(t("Отдельная модель: она не отвечает словами, а считает смысл."))
                installRow(RecommendedModel.embed)
            }
            .disabled(!settings.ollamaEnabled)

            VStack(alignment: .leading, spacing: 4) {
                Picker(t("Насколько близкими считать"), selection: settings.binding(\.obsidianLinkThreshold)) {
                    ForEach([60, 70, 80, 90], id: \.self) { value in
                        Text(tf("%d%%", value)).tag(value)
                    }
                }
                .pickerStyle(.menu)
                hint(t("Ниже — связей больше, но случайных тоже."))
            }
            .accessibilityElement(children: .combine)
            .disabled(!settings.obsidianLinksEnabled || !settings.ollamaEnabled)

            VStack(alignment: .leading, spacing: 4) {
                Toggle(t("Только у новых заметок"), isOn: settings.binding(\.linksOnlyNew))
                hint(t("У большого архива первый проход — часы работы модели."))
                if settings.linksOnlyNew, settings.linksSince != nil {
                    Button(t("Связать и старые")) {
                        settings.linksSince = nil
                        linker.refreshAll()
                    }
                }
            }
            .disabled(!settings.obsidianLinksEnabled || !settings.ollamaEnabled)

            VStack(alignment: .leading, spacing: 4) {
                Toggle(t("Дописывать связи в файлы Obsidian"), isOn: settings.binding(\.obsidianLinksToFiles))
                hint(t("Отдельным блоком между невидимыми метками — в графе они станут настоящими ссылками."))
            }
            .accessibilityElement(children: .combine)
            .disabled(!settings.obsidianLinksEnabled || !settings.obsidianEnabled)

            VStack(alignment: .leading, spacing: 4) {
                Button(t("Убрать блоки связей из файлов"), action: obsidian.removeAllLinkBlocks)
                    .disabled(!settings.obsidianEnabled)
                hint(t("Снимает их подчистую. Остальной текст файлов не трогает."))
            }
        }
    }

    /// Выбор модели, считающей векторы.
    ///
    /// Список тот же, что и у обычных моделей, — Ollama не разделяет их
    /// у себя, — но выбранное показывается даже когда список не пришёл:
    /// пустое поле выглядело бы как «модель не выбрана», а она выбрана,
    /// просто сервер сейчас молчит.
    var embedModelPicker: some View {
        let provider = settings.aiProvider
        let found = models.models(of: provider, kind: .embedding)
        let current = ModelRef.parse(settings.embedModel, fallback: provider)?.name ?? ""
        return HStack {
            Picker(t("Модель для векторов"), selection: Binding(
                get: { current },
                set: { settings.embedModel = ModelRef(provider: provider, name: $0).stored }
            )) {
                if !found.contains(where: { $0.name == current }) {
                    Text(current.isEmpty ? t("не выбрана") : current).tag(current)
                }
                ForEach(found, id: \.self) { model in
                    Text(model.name).tag(model.name)
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
            .help(t("Обновить список"))
            .accessibilityLabel(t("Обновить список"))
        }
    }

    /// Карточка записи разговора.
    ///
    /// Целиком в разделе «Заметки», а не своим разделом: результат записи —
    /// обычная заметка, и человек ищет её там же, где остальное про заметки.
    @ViewBuilder
    var recordCard: some View {
        section(t("Запись разговора"), icon: "waveform") {
            if !RecorderService.isSupported {
                hint(t("Расшифровка на устройстве появилась в macOS 26."))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Запись разговора"), isOn: settings.binding(\.recordEnabled))
                        .disabled(!settings.notesEnabled)
                    hint(t("Кнопка записи появится в панели встречи и в заметке."))
                }
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(t("Аудиозаметка"))
                        Spacer()
                        HotKeyRecorder(label: t("Аудиозаметка"), spec: Binding(
                            get: { settings.recordHotKey },
                            set: { settings.recordHotKey = $0; onHotKeysChanged() }
                        ))
                        .frame(width: SettingsStyle.hotKeyField.width,
                               height: SettingsStyle.hotKeyField.height)
                    }
                    hint(t("Нажатие начинает запись, повторное — заканчивает."))
                }
                .disabled(!settings.notesEnabled || !settings.recordEnabled)

                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Язык расшифровки"), selection: Binding(
                        get: { settings.transcribeLanguage },
                        set: {
                            settings.transcribeLanguage = $0
                            transcripts.refresh(for: settings.transcribeLocale)
                        }
                    )) {
                        Text(t("Как в системе")).tag("")
                        ForEach(transcripts.locales, id: \.identifier) { locale in
                            Text(TranscriptAssets.name(of: locale)).tag(locale.identifier)
                        }
                    }
                    transcriptRow
                }
                .disabled(!settings.notesEnabled || !settings.recordEnabled)
                .onAppear {
                    transcripts.loadLocales()
                    transcripts.refresh(for: settings.transcribeLocale)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Хранить записи"), selection: settings.binding(\.audioRetentionDays)) {
                        ForEach(AudioRetention.choices, id: \.self) { days in
                            Text(AudioRetention.title(days: days)).tag(days)
                        }
                    }
                    .pickerStyle(.menu)
                    hint(t("Текст заметки остаётся, удаляется только звук."))
                }
                .accessibilityElement(children: .combine)
                .disabled(!settings.notesEnabled)

                hint(tf("Записи лежат рядом с заметками, в папке «%@».", RecorderService.folderName))
            }
        }
    }

    /// Состояние языкового набора и кнопка «Скачать».
    ///
    /// Набор нужен обязательно: без него расшифровка молча отдаёт пустой
    /// текст, и заметка выходит с одним аудиофайлом. Поэтому состояние
    /// показывается всегда, а не только когда что-то пошло не так.
    @ViewBuilder
    var transcriptRow: some View {
        switch transcripts.state {
        case let .downloading(share):
            HStack(spacing: SettingsStyle.gap) {
                ProgressView(value: share).controlSize(.small)
                Text(tf("Качаю язык — %d%%", Int(share * 100)))
                    .foregroundStyle(SettingsStyle.tertiary)
            }
        case .installed:
            hint(t("Язык установлен, расшифровка идёт на этом компьютере."))
        case .missing:
            HStack(spacing: SettingsStyle.gap) {
                Button(t("Скачать язык")) { transcripts.install(for: settings.transcribeLocale) }
                Text(t("Без него расшифровки не будет"))
                    .foregroundStyle(SettingsStyle.tertiary)
            }
        case .unsupportedLanguage:
            hint(t("Этот язык расшифровка не знает."))
        case let .failed(text):
            HStack(spacing: SettingsStyle.gap) {
                Button(t("Скачать язык")) { transcripts.install(for: settings.transcribeLocale) }
                Text(text).foregroundStyle(Palette.warning)
            }
        case .unknown, .unsupported:
            EmptyView()
        }
    }

    /// Строка «этой модели нет — скачать».
    ///
    /// Показывается только когда модели и правда нет: у того, у кого она уже
    /// стоит, кнопка была бы предложением сделать сделанное. Пока идёт
    /// загрузка, на её месте полоса — модель весит гигабайты, и кнопка
    /// без отклика читалась бы как несработавшая.
    @ViewBuilder
    func installRow(_ name: String) -> some View {
        if installer.isInstalling(name) {
            HStack(spacing: SettingsStyle.gap) {
                ProgressView(value: installedShare).controlSize(.small)
                Text(tf("Качаю %@ — %d%%", name, Int(installedShare * 100)))
                    .foregroundStyle(SettingsStyle.tertiary)
                Button(t("Отменить"), action: installer.cancel)
            }
        } else if !isInstalled(name), settings.aiProvider == .ollama {
            HStack(spacing: SettingsStyle.gap) {
                Button(tf("Скачать %@", name)) { installer.install(name) }
                    .disabled(installer.isBusy)
                if case .failed(let text) = installer.state {
                    Text(text)
                        .foregroundStyle(Palette.warning)
                        .lineLimit(1)
                }
            }
        }
    }

    /// Есть ли такая модель. Для векторной достаточно **любой** векторной:
    /// человек мог скачать не рекомендованную, а другую, и предлагать ему
    /// вторую такую же незачем.
    func isInstalled(_ name: String) -> Bool {
        if name == RecommendedModel.embed {
            return !models.models(of: settings.aiProvider, kind: .embedding).isEmpty
        }
        return RecommendedModel.isInstalled(name, among: models.models(of: .ollama))
    }

    var installedShare: Double {
        if case .pulling(let share) = installer.state { return share }
        return 0
    }

    /// Выключенные связи не оставляют за собой ничего: ни векторов, ни связей.
    func linksChanged() {
        guard settings.obsidianLinksEnabled else {
            settings.linksSince = nil
            linker.clearLinks()
            return
        }
        // Граница «новизны» ставится в тот миг, когда связи включили:
        // всё, что человек запишет после, — новое.
        if settings.linksSince == nil { settings.linksSince = Date() }
        linker.refreshAll()
    }

    /// Карточка Obsidian.
    ///
    /// Стоит внутри «Заметок», а не отдельным разделом слева: разделов
    /// и так девять, а это по существу заметки. Всё, кроме переключателя,
    /// гаснет при выключенной синхронизации — прячется только выбор папки,
    /// потому что без него остальное бессмысленно.
    var obsidianSection: some View {
        section(t("Obsidian"), icon: "circle.hexagongrid") {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(t("Синхронизация с Obsidian"), isOn: Binding(
                    get: { settings.obsidianEnabled },
                    set: { settings.obsidianEnabled = $0; obsidian.settingsChanged() }
                ))
                hint(t("Заметки лягут в хранилище файлами, а его заметки найдутся поиском."))
            }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(vaultPathTitle)
                        .foregroundStyle(settings.obsidianVaultPath.isEmpty
                            ? SettingsStyle.tertiary : SettingsStyle.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                    Button(t("Выбрать папку…"), action: chooseVault)
                }
                hint(vaultHint)
            }
            .disabled(!settings.obsidianEnabled)

            VStack(alignment: .leading, spacing: 4) {
                field(
                    t("Папка для заметок"),
                    prompt: Vault.defaultFolder,
                    text: Binding(
                        get: { settings.obsidianFolder },
                        set: { settings.obsidianFolder = $0 }
                    )
                )
                hint(t("Внутри хранилища. Можно вложенную: «Заметки/Trunook»."))
            }
            .disabled(!settings.obsidianEnabled)
            .onSubmit { obsidian.folderChanged() }

            VStack(alignment: .leading, spacing: 4) {
                Toggle(t("Искать и по заметкам хранилища"), isOn: Binding(
                    get: { settings.obsidianIndexVault },
                    set: { settings.obsidianIndexVault = $0; obsidian.sync(manual: true) }
                ))
                hint(t("Они появляются в поиске и уходят в контекст модели. Править их можно только в Obsidian."))
            }
            .accessibilityElement(children: .combine)
            .disabled(!settings.obsidianEnabled)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(obsidianStateText)
                        .foregroundStyle(obsidianStateColor)
                    Spacer()
                    Button(t("Синхронизировать"), action: { obsidian.sync(manual: true) })
                        .disabled(!settings.obsidianEnabled || settings.obsidianVaultPath.isEmpty)
                }
                hint(tf("Свои заметки лежат в подпапке «%@». Остальное хранилище приложение только читает.", settings.obsidianFolder))
            }
            .disabled(!settings.obsidianEnabled)
        }
    }

    var vaultPathTitle: String {
        let path = settings.obsidianVaultPath
        return path.isEmpty ? t("Папка не выбрана") : (path as NSString).abbreviatingWithTildeInPath
    }

    /// Предупреждения — короткой фразой и только по делу: папка не выбрана,
    /// папка пропала, папка не похожа на хранилище.
    var vaultHint: String {
        guard !settings.obsidianVaultPath.isEmpty else {
            return t("У Obsidian нет постоянного места — папку называете вы.")
        }
        guard let vault = obsidian.vault else { return t("У Obsidian нет постоянного места — папку называете вы.") }
        if !vault.isReachable { return t("Папка не читается: диск отключён или её переименовали.") }
        if !vault.looksLikeVault { return t("Внутри нет папки .obsidian — на хранилище не похоже.") }
        return t("Приложение пишет в эту папку. Удаляет только в Корзину.")
    }

    var obsidianStateText: String {
        switch obsidian.state {
        case .off: return t("Выключено")
        case .noFolder: return t("Папка не выбрана")
        case .unreachable: return t("Папка недоступна — ничего не тронуто")
        case .emptied: return t("Файлов вдруг стало меньше — сверка остановлена")
        case .syncing: return t("Сверяю…")
        case .never: return t("Сверки ещё не было")
        case .synced(let date): return tf("Сверено в %@", Self.timeText(date))
        }
    }

    var obsidianStateColor: Color {
        switch obsidian.state {
        case .unreachable, .emptied: return Palette.warning
        default: return SettingsStyle.secondary
        }
    }

    static func timeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Localization.shared.resolved.locale
        formatter.setLocalizedDateFormatFromTemplate("HH:mm")
        return formatter.string(from: date)
    }

    /// Папку называет человек. Ни одного предположения о том, где хранилище
    /// лежит, в коде нет: у Obsidian нет постоянного места, и угаданный путь
    /// однажды оказался бы не тем.
    func chooseVault() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = t("Выбрать")
        panel.message = t("Где лежит хранилище Obsidian")
        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK, let folder = panel.url else { return }
        settings.obsidianVaultPath = folder.path
        obsidian.settingsChanged()
        obsidian.sync(manual: true)
    }

    /// Очистка спрашивает подтверждение: это единственный способ потерять
    /// все заметки разом, а мимо кнопки в настройках попадают так же,
    /// как и везде.
    func clearNotes() {
        let alert = NSAlert()
        alert.messageText = t("Удалить все заметки?")
        alert.informativeText = t("Вернуть их будет нельзя. Выгрузите их в папку, если они ещё пригодятся.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: t("Удалить"))
        alert.addButton(withTitle: t("Отмена"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        notes.clearAll()
    }
}
