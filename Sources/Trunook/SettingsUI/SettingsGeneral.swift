import AVFoundation
import AppKit
import SwiftUI

/// Раздел настроек «Основные»: обновления, система, доступы, сочетания клавиш.
extension SettingsView {
    /// Подпись варианта в списке сроков плашек.
    ///
    /// Словами, а не «в N раз дольше» с подстановкой: «в 3 раза» и «в 10 раз»
    /// склоняются по-разному, и одна строка формата дала бы «в 10 раза».
    static func activityHoldTitle(_ scale: Int) -> String {
        switch scale {
        case 0: return t("Пока не уберу")
        case 1: return t("Как обычно")
        case 3: return t("Втрое дольше")
        case 10: return t("Вдесятеро дольше")
        default: return tf("В %d раз дольше", scale)
        }
    }

    /// Состояние проверки и кнопка рядом с ним.
    ///
    /// Текст и подпись кнопки приходят из одной `UpdateStatusText.line(for:)`:
    /// «Готово к установке» рядом с кнопкой «Проверить» было бы не опечаткой,
    /// а обещанием, которого приложение не выполнит.
    @ViewBuilder
    var updateStatusRow: some View {
        let line = UpdateStatusText.line(for: updates.state)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(line.text).foregroundStyle(.secondary)
                // Раньше здесь стояла ссылка на страницу GitHub, и появлялась
                // она только у скачанного обновления. В остальное время
                // карточка обновлений не отзывалась ни на что — а «что там
                // нового» спрашивают как раз чаще до загрузки, чем после.
                // Теперь кнопка стоит всегда и ведёт не в браузер, а в окно
                // знакомства: описание выпусков приложение показывает само.
                Button(t("Что нового")) { onOpenReleaseNotes() }
                    .buttonStyle(.link)
                Spacer()
                switch line.action {
                case .check:
                    Button(t("Проверить")) { updates.check(manual: true) }
                case .install:
                    Button(t("Обновить")) { updates.install() }
                case .busy:
                    Button(t("Проверить")) {}.disabled(true)
                }
            }
            if case .install = line.action {
                hint(t("Приложение перезапустится. Доступы останутся выданными."))
            }
        }
    }

    var generalSection: some View {
        Group {
                // Первой карточкой: с обновлением человек приходит сюда
                // по плашке из выреза, и искать его среди мурчания и размера
                // текста ему незачем.
                section(t("Обновления"), icon: "arrow.down.circle") {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(t("Проверять обновления"), isOn: settings.binding(\.autoUpdateEnabled))
                        hint(t("Раз в сутки спрашивает GitHub и скачивает новую версию фоном."))
                    }
                    .accessibilityElement(children: .combine)
                    HStack {
                        Text(t("Версия"))
                        Spacer()
                        Text(AppInfo.version).textSelection(.enabled)
                            .foregroundStyle(.secondary)
                    }
                    updateStatusRow
                }

                section(t("Система"), icon: "desktopcomputer") {
                    Picker(t("Язык интерфейса"), selection: Binding(
                        get: { settings.language },
                        set: { settings.language = $0 }
                    )) {
                        ForEach(Language.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .pickerStyle(.menu)

                    Toggle(t("Запускать при входе в систему"), isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.isEnabled = $0 }
                    ))

                    VStack(alignment: .leading, spacing: 4) {
                        Picker(t("Размер текста"), selection: Binding(
                            get: { settings.textScale },
                            set: { settings.textScale = $0; onLayoutChanged() }
                        )) {
                            ForEach(Settings.textScales, id: \.self) { scale in
                                Text(tf("%d %%", scale)).tag(scale)
                            }
                        }
                        .pickerStyle(.menu)
                        hint(t("Действует в этом окне и в окне знакомства."))
                    }
                    .accessibilityElement(children: .combine)
                }

                permissionsCard
                hotKeysCard
        }
    }

    /// Все доступы с состоянием и кнопкой. Раньше их выдавали только
    /// в знакомстве, а в настройках было три пояснения «Нужен Универсальный
    /// доступ» без состояния и без кнопки.
    var permissionsCard: some View {
        section(t("Доступы"), icon: "lock.shield") {
            ForEach(PermissionCenter.Permission.allCases) { permission in
                let state = permissions.state(of: permission)
                let needed = permissions.isRequired(permission) && state != .granted
                HStack(spacing: 10) {
                    Image(systemName: permission.icon)
                        .foregroundStyle(needed ? Palette.warning : SettingsStyle.secondary)
                        .frame(width: SettingsStyle.glyphSide)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(permission.title)
                        Text(needed ? tf("%@ — нужен включённым функциям", state.label) : state.label)
                            .font(.system(size: SettingsStyle.font(11.5)))
                            .foregroundStyle(needed ? Palette.warning : SettingsStyle.tertiary)
                    }
                    Spacer()
                    if state != .granted {
                        Button(permissions.actionTitle(for: permission)) { permissions.act(on: permission) }
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Palette.positive)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint(permission.explanation)
            }
        }
        .onAppear { permissions.start() }
        .onDisappear { permissions.stop() }
    }

    /// Сочетание в общем списке: название, путь к значению.
    struct HotKeyEntry: Identifiable {
        let title: String
        let key: ReferenceWritableKeyPath<Settings, HotKeySpec?>
        var id: String { title }
    }

    var hotKeyEntries: [HotKeyEntry] {
        var entries = [
            HotKeyEntry(title: t("Раскрыть панель"), key: \.expandedHotKey),
            HotKeyEntry(title: t("Спросить о выделенном"), key: \.assistantHotKey),
        ]
        if settings.voiceTrigger == .hotKey {
            entries.append(HotKeyEntry(title: t("Голосовой ассистент"), key: \.voiceHotKey))
        }
        entries += [
            HotKeyEntry(title: t("Новая заметка"), key: \.notesHotKey),
            HotKeyEntry(title: t("Выделенное в заметки"), key: \.noteSelectionHotKey),
            HotKeyEntry(title: t("Аудиозаметка"), key: \.recordHotKey),
            HotKeyEntry(title: t("Открыть календарь"), key: \.calendarHotKey),
            HotKeyEntry(title: t("Открыть сводки"), key: \.feedsHotKey),
            HotKeyEntry(title: t("Открыть историю"), key: \.clipboardHotKey),
            HotKeyEntry(title: t("Открыть полку"), key: \.shelfHotKey),
            HotKeyEntry(title: t("Открыть таймер"), key: \.timerHotKey),
            HotKeyEntry(title: t("Открыть нагрузку"), key: \.monitorHotKey),
            HotKeyEntry(title: t("Открыть телесуфлер"), key: \.teleprompterHotKey),
        ]
        return entries
    }

    /// Все сочетания разом — чтобы увидеть, какое занято, не обходя восемь
    /// разделов. Поля в карточках функций остаются: значение одно, путей два.
    /// Занятое дважды — сочетаниями функций или команд — помечено.
    var hotKeysCard: some View {
        let entries = hotKeyEntries
        var used: [HotKeySpec: [String]] = [:]
        for entry in entries {
            if let spec = settings[keyPath: entry.key] { used[spec, default: []].append(entry.title) }
        }
        for command in settings.quickCommands {
            if let spec = command.hotKey { used[spec, default: []].append(sectionTitle(for: command)) }
        }
        return section(t("Сочетания клавиш"), icon: "keyboard") {
            ForEach(entries) { entry in
                let spec = settings[keyPath: entry.key]
                let clash = spec.flatMap { used[$0] }?.filter { $0 != entry.title } ?? []
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.title)
                        Spacer()
                        HotKeyRecorder(label: entry.title, spec: Binding(
                            get: { settings[keyPath: entry.key] },
                            set: { settings[keyPath: entry.key] = $0; onHotKeysChanged() }
                        ))
                        .frame(width: SettingsStyle.hotKeyField.width,
                               height: SettingsStyle.hotKeyField.height)
                    }
                    if !clash.isEmpty {
                        Text(tf("Занято и у: %@", clash.joined(separator: ", ")))
                            .font(.system(size: SettingsStyle.font(11.5)))
                            .foregroundStyle(Palette.warning)
                    }
                }
            }
            hint(t("Сочетания команд — в разделе «Команды»."))
        }
    }
}
