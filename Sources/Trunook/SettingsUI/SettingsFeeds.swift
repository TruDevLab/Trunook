import AVFoundation
import AppKit
import SwiftUI

/// Раздел настроек «Сводки»: новости и слежка за сайтами.
extension SettingsView {
    var feedsSection: some View {
        Group {
            if !settings.ollamaEnabled {
                modelRequiredCard(t("Сводки и слежку собирает модель."))
            }
            digestSection
            siteWatchSection
            section(t("Панель сводок"), icon: "keyboard") {
                HStack {
                    Text(t("Открыть сводки"))
                    Spacer()
                    HotKeyRecorder(label: t("Открыть сводки"), spec: Binding(
                        get: { settings.feedsHotKey },
                        set: { settings.feedsHotKey = $0; onHotKeysChanged() }
                    ))
                    .frame(width: SettingsStyle.hotKeyField.width,
                           height: SettingsStyle.hotKeyField.height)
                }
                .disabled(!settings.digestEnabled && !settings.siteWatchEnabled)
            }
        }
    }

    var digestSection: some View {
        section(t("Сводка новостей"), icon: "newspaper") {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(t("Сводка новостей"), isOn: Binding(
                    get: { settings.digestEnabled },
                    set: { isOn in
                        settings.digestEnabled = isOn
                        // Отсчёт — от включения: давно пропущенный срок
                        // не должен собрать сводку в ту же секунду.
                        if isOn { settings.lastDigestRun = Date() }
                        onHotKeysChanged()
                    }
                ))
                hint(t("По каждой теме — до пяти главных новостей со ссылками."))
            }

            ForEach(settings.digestTopics) { topic in
                HStack(spacing: SettingsStyle.gap) {
                    Toggle("", isOn: Binding(
                        get: { topic.isEnabled },
                        set: { var updated = topic; updated.isEnabled = $0; settings.updateDigestTopic(updated) }
                    ))
                    .labelsHidden()
                    TextField(text: Binding(
                        get: { topic.title },
                        set: { var updated = topic; updated.title = $0; settings.updateDigestTopic(updated) }
                    ), prompt: Text(t("Тема"))) { EmptyView() }
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    Button { settings.removeDigestTopic(id: topic.id) } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(t("Удалить тему"))
                }
                .disabled(!settings.digestEnabled)
            }

            HStack(spacing: SettingsStyle.gap) {
                TextField(text: $selection.newDigestTopic,
                          prompt: Text(t("Новая тема, например «новинки кино»"))) { EmptyView() }
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addDigestTopic)
                Button(t("Добавить"), action: addDigestTopic)
                    .disabled(selection.newDigestTopic.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .disabled(!settings.digestEnabled)

            topicSuggestions
                .disabled(!settings.digestEnabled)

            VStack(alignment: .leading, spacing: 6) {
                weekdayRow
                DatePicker(t("Время"), selection: digestTimeBinding, displayedComponents: .hourAndMinute)
            }
            .disabled(!settings.digestEnabled)

            VStack(alignment: .leading, spacing: 4) {
                Picker(t("Модель"), selection: settings.binding(\.digestModel)) {
                    Text(t("Как в разговоре")).tag("")
                    ForEach(chatModelChoices(keeping: settings.digestModel), id: \.self) { choice in
                        Text(ModelRef.parse(choice, fallback: settings.aiProvider)?.shortName ?? choice)
                            .tag(choice)
                    }
                }
                .pickerStyle(.menu)
                hint(t("Та же модель ищет значения на сайтах."))
            }
            .accessibilityElement(children: .combine)
            .disabled(!settings.ollamaEnabled)
            .onAppear { if settings.ollamaEnabled { models.refreshIfNeeded() } }

            HStack {
                Text(digestStatus)
                    .font(.callout)
                    .foregroundStyle(digest.lastFailed ? Palette.warning : .secondary)
                Spacer()
                Button(t("Собрать сейчас")) { digest.run(manual: true) }
                    .disabled(digest.isRunning || digest.activeTopics.isEmpty || !settings.ollamaEnabled)
            }
        }
    }

    /// Подсказка тем: модель предлагает, человек отмечает галочками.
    var topicSuggestions: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: SettingsStyle.gap) {
                Button {
                    selection.chosenTopicSuggestions = []
                    digest.suggestTopics(noteTitles: notes.notes.map(\.title))
                } label: {
                    Label(t("Предложить темы"), systemImage: "sparkles")
                }
                .disabled(digest.isSuggesting || !settings.ollamaEnabled)
                if digest.isSuggesting {
                    ProgressView().controlSize(.small)
                    Text(t("Подбираю темы…"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            hint(digest.suggestionsUseNotes
                 ? t("Модель учтёт названия заметок — они не покидают компьютер.")
                 : t("Модель облачная — заметки ей не показываются."))

            if !digest.suggestions.isEmpty {
                ForEach(digest.suggestions, id: \.self) { title in
                    Toggle(title, isOn: Binding(
                        get: { selection.chosenTopicSuggestions.contains(title) },
                        set: { isOn in
                            if isOn {
                                selection.chosenTopicSuggestions.insert(title)
                            } else {
                                selection.chosenTopicSuggestions.remove(title)
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
                HStack(spacing: SettingsStyle.gap) {
                    Button(tf("Добавить отмеченные: %d", selection.chosenTopicSuggestions.count)) {
                        digest.accept(selection.chosenTopicSuggestions)
                        selection.chosenTopicSuggestions = []
                    }
                    .disabled(selection.chosenTopicSuggestions.isEmpty)
                    Button(t("Скрыть")) {
                        digest.clearSuggestions()
                        selection.chosenTopicSuggestions = []
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }

    func addDigestTopic() {
        let title = selection.newDigestTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        settings.addDigestTopic(title)
        selection.newDigestTopic = ""
    }

    var digestStatus: String {
        if digest.isRunning { return digest.progress ?? t("Собираю сводку…") }
        if digest.lastFailed { return t("Сводка не собралась — проверьте сеть и модель") }
        guard let last = digest.digests.first else { return t("Сводок пока не было") }
        return tf("Последняя сводка — %@", Self.feedStamp(last.createdAt))
    }

    /// Дни недели кнопками, с первого дня недели по календарю системы.
    var weekdayRow: some View {
        var calendar = Calendar.current
        calendar.locale = Localization.shared.resolved.locale
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
        let chosen = settings.digestSchedule.weekdays
        return HStack(spacing: 4) {
            ForEach(order, id: \.self) { day in
                let isOn = chosen.contains(day)
                Button {
                    var schedule = settings.digestSchedule
                    if isOn { schedule.weekdays.remove(day) } else { schedule.weekdays.insert(day) }
                    settings.digestSchedule = schedule
                } label: {
                    Text(symbols[day - 1])
                        .font(.callout.weight(isOn ? .semibold : .regular))
                        .frame(minWidth: 30)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isOn ? Palette.feeds.opacity(0.35) : Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
    }

    var digestTimeBinding: Binding<Date> {
        Binding(
            get: {
                let schedule = settings.digestSchedule
                return Calendar.current.date(
                    bySettingHour: schedule.hour, minute: schedule.minute, second: 0, of: Date()
                ) ?? Date()
            },
            set: { date in
                var schedule = settings.digestSchedule
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                schedule.hour = parts.hour ?? schedule.hour
                schedule.minute = parts.minute ?? schedule.minute
                settings.digestSchedule = schedule
            }
        )
    }

    var siteWatchSection: some View {
        section(t("Слежка за сайтами"), icon: "binoculars") {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(t("Слежка за сайтами"), isOn: Binding(
                    get: { settings.siteWatchEnabled },
                    set: { settings.siteWatchEnabled = $0; onHotKeysChanged() }
                ))
                hint(t("Любое значение на странице — цена, наличие, дата, строка текста."))
            }
            .accessibilityElement(children: .combine)

            ForEach(settings.siteWatches) { watch in
                siteWatchRow(watch)
                    .disabled(!settings.siteWatchEnabled)
            }

            VStack(alignment: .leading, spacing: 6) {
                TextField(text: $selection.newSiteURL, prompt: Text(t("Ссылка на страницу"))) { EmptyView() }
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                HStack(spacing: SettingsStyle.gap) {
                    TextField(text: $selection.newSiteTarget, prompt: Text(t("За чем следить: цена, наличие, дата, любой текст"))) {
                        EmptyView()
                    }
                    .onSubmit(addSiteWatch)
                    Button(t("Добавить"), action: addSiteWatch)
                        .disabled(newSiteURL == nil || newSiteTarget.isEmpty)
                }
            }
            .disabled(!settings.siteWatchEnabled)
        }
    }

    var newSiteURL: URL? {
        SiteWatch(id: 0, url: selection.newSiteURL, name: "", target: "").pageURL
    }

    var newSiteTarget: String {
        selection.newSiteTarget.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func addSiteWatch() {
        guard newSiteURL != nil, !newSiteTarget.isEmpty else { return }
        let id = settings.addSiteWatch(url: selection.newSiteURL, target: newSiteTarget)
        selection.newSiteURL = ""
        selection.newSiteTarget = ""
        // Первая проверка сразу: человек должен увидеть, то ли нашлось,
        // пока он ещё здесь, а не через час.
        if settings.siteWatchEnabled { siteWatch.check(id: id) }
    }

    func siteWatchRow(_ watch: SiteWatch) -> some View {
        let state = siteWatch.state(of: watch)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: SettingsStyle.gap) {
                Toggle("", isOn: Binding(
                    get: { watch.isEnabled },
                    set: { var updated = watch; updated.isEnabled = $0; settings.updateSiteWatch(updated) }
                ))
                .labelsHidden()
                TextField(text: Binding(
                    get: { watch.name },
                    set: { var updated = watch; updated.name = $0; settings.updateSiteWatch(updated) }
                ), prompt: Text(watch.displayName)) { EmptyView() }
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                Button {
                    settings.removeSiteWatch(id: watch.id)
                    siteWatch.reset(id: watch.id)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help(t("Перестать следить"))
            }
            Text(watch.url)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: SettingsStyle.gap) {
                TextField(text: Binding(
                    get: { watch.target },
                    set: { var updated = watch; updated.target = $0; settings.updateSiteWatch(updated) }
                ), prompt: Text(t("За чем следить"))) { EmptyView() }
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                Picker("", selection: Binding(
                    get: { watch.condition },
                    set: { var updated = watch; updated.condition = $0; settings.updateSiteWatch(updated) }
                )) {
                    ForEach(WatchCondition.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 150)
                if watch.condition.usesThreshold {
                    TextField("", value: Binding(
                        get: { watch.threshold },
                        set: { var updated = watch; updated.threshold = $0; settings.updateSiteWatch(updated) }
                    ), format: .number)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 80)
                }
            }
            HStack(spacing: SettingsStyle.gap) {
                Picker("", selection: Binding(
                    get: { watch.interval },
                    set: { var updated = watch; updated.interval = $0; settings.updateSiteWatch(updated) }
                )) {
                    ForEach(WatchInterval.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 170)
                Spacer()
                if state.status == .blocked {
                    Button(t("Пройти проверку")) { siteWatch.openForVerification(watch) }
                }
                Button(t("Проверить")) { siteWatch.check(id: watch.id) }
                    .disabled(siteWatch.checkingID == watch.id)
            }
            Text(siteStatus(watch, state))
                .font(.callout)
                .foregroundStyle(state.status == .ok || state.status == .waiting ? .secondary : Palette.warning)
            if watch.condition.needsNumber, let reading = state.reading, reading.number == nil {
                Text(t("В значении нет одного числа — это условие не сработает, выберите «Любое изменение»."))
                    .font(.callout)
                    .foregroundStyle(Palette.warning)
            }
        }
        .padding(.vertical, 2)
    }

    func siteStatus(_ watch: SiteWatch, _ state: WatchState) -> String {
        if siteWatch.checkingID == watch.id { return t("Проверяю…") }
        switch state.status {
        case .waiting: return t("Ещё не проверялся")
        case .ok:
            let value = state.reading?.text ?? "—"
            let checked = state.checkedAt.map(Self.feedStamp) ?? ""
            return tf("Сейчас: %@ · проверено %@", value, checked)
        case .blocked: return t("Сайт не пустил проверку — откройте его и пройдите проверку")
        case .notFound: return t("На странице не нашлось — уточните, за чем следить")
        case .failed: return t("Не удалось проверить — сеть или модель")
        }
    }

    static func feedStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Localization.shared.resolved.locale
        formatter.setLocalizedDateFormatFromTemplate("d MMM HH:mm")
        return formatter.string(from: date)
    }
}
