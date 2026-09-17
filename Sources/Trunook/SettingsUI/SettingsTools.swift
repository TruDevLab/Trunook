import AVFoundation
import AppKit
import SwiftUI

/// Раздел настроек «Инструменты»: буфер, полка, окна, таймер, перерывы, нагрузка, телесуфлер, чашка.
extension SettingsView {
    /// Очистка истории буфера — с подтверждением, как у заметок: вернуть
    /// записи нельзя, а мимо кнопки попадают так же, как везде.
    func clearClipboard() {
        let alert = NSAlert()
        alert.messageText = t("Очистить историю буфера?")
        alert.informativeText = t("Все сохранённые копирования удалятся. Вернуть их будет нельзя.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: t("Очистить"))
        alert.addButton(withTitle: t("Отмена"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        clipboard.clear()
    }

    var teleprompterSection: some View {
        Group {
            section(t("Телесуфлер"), icon: "text.alignleft") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(t("Открыть телесуфлер"))
                        Spacer()
                        HotKeyRecorder(label: t("Открыть телесуфлер"), spec: Binding(
                            get: { settings.teleprompterHotKey },
                            set: { settings.teleprompterHotKey = $0; onHotKeysChanged() }
                        ))
                        .frame(width: SettingsStyle.hotKeyField.width,
                                   height: SettingsStyle.hotKeyField.height)
                    }
                    hint(t("Нажатие при открытой панели закрывает её."))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Скорость прокрутки"), selection: settings.binding(\.teleprompterSpeed)) {
                        ForEach([10, 20, 40, 60, 90, 120], id: \.self) { value in
                            Text(tf("%d т/с", value)).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    hint(t("Точек в секунду. То же есть ползунком в самой панели."))
                }
                .accessibilityElement(children: .combine)
            }

            section(t("Как он устроен"), icon: "questionmark.circle") {
                // Справочная карточка: сплошной текст абзацами, а не список
                // настроек. Одной строкой — чтобы `Form` не расчерчивал абзацы
                // разделителями, будто каждый из них что-то отдельное включает.
                VStack(alignment: .leading, spacing: SettingsStyle.gap) {
                    hint(t("Не закрывается щелчком мимо. Убрать — крестиком или клавишей."))
                    hint(t("Текст сохраняется до кнопки «Очистить»."))
                    hint(t("Заголовок, начертания, ссылки и эмодзи."))
                    hint(tf("Хранится в %@ — в формате RTF, вместе с оформлением.", TeleprompterStore.fileURL.path))
                }
            }
        }
    }

    var monitorSection: some View {
        Group {
            section(t("Нагрузка на систему"), icon: "gauge.with.dots.needle.67percent") {
                Toggle(t("Нагрузка на систему"), isOn: Binding(
                    get: { settings.monitorEnabled },
                    set: { settings.monitorEnabled = $0; onHotKeysChanged() }
                ))

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(t("Открыть нагрузку"))
                        Spacer()
                        HotKeyRecorder(label: t("Открыть нагрузку"), spec: Binding(
                            get: { settings.monitorHotKey },
                            set: { settings.monitorHotKey = $0; onHotKeysChanged() }
                        ))
                        .frame(width: SettingsStyle.hotKeyField.width,
                                   height: SettingsStyle.hotKeyField.height)
                    }
                    .disabled(!settings.monitorEnabled)

                    hint(t("Процессор, память и диск. Нажатие открывает Мониторинг системы."))
                }
            }

            section(t("Что показано и чего нет"), icon: "questionmark.circle") {
                // Справочная карточка: сплошной текст абзацами, а не список
                // настроек. Одной строкой — чтобы `Form` не расчерчивал абзацы
                // разделителями, будто каждый из них что-то отдельное включает.
                VStack(alignment: .leading, spacing: SettingsStyle.gap) {
                    hint(t("Считается как в Мониторинге системы."))
                    hint(t("Том с данными, не системный."))
                    hint(t("Видеокарты нет: macOS не отдаёт её загрузку."))
                    hint(t("Опрашивается только при открытой панели."))
                }
            }
        }
    }

    var timerSection: some View {
        Group {
            section(t("Таймер и секундомер"), icon: "timer") {
                Toggle(t("Таймер и секундомер"), isOn: Binding(
                    get: { settings.timerEnabled },
                    set: { settings.timerEnabled = $0; onHotKeysChanged() }
                ))

                HStack {
                    Text(t("Открыть таймер"))
                    Spacer()
                    HotKeyRecorder(label: t("Открыть таймер"), spec: Binding(
                        get: { settings.timerHotKey },
                        set: { settings.timerHotKey = $0; onHotKeysChanged() }
                    ))
                    .frame(width: SettingsStyle.hotKeyField.width,
                                   height: SettingsStyle.hotKeyField.height)
                }
                .disabled(!settings.timerEnabled)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Звук"), isOn: settings.binding(\.timerSoundEnabled))
                        .disabled(!settings.timerEnabled)
                    hint(t("Щелчки при выборе времени и один сигнал по окончании."))
                }
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("После работы заводить перерыв"),
                           isOn: settings.binding(\.pomodoroChainsRest))
                        .disabled(!settings.timerEnabled)
                    hint(t("Двадцать пять минут работы, пять перерыва."))
                }
                .accessibilityElement(children: .combine)
            }

            section(t("Как это устроено"), icon: "clock.arrow.circlepath") {
                // Справочная карточка: сплошной текст абзацами, а не список
                // настроек. Одной строкой — чтобы `Form` не расчерчивал абзацы
                // разделителями, будто каждый из них что-то отдельное включает.
                VStack(alignment: .leading, spacing: SettingsStyle.gap) {
                    hint(t("Пока таймер идёт, чёлка показывает счёт."))
                }
            }
        }
    }

    /// Напоминания о перерыве, воде и разминке — у каждого свой промежуток.
    var breaksCard: some View {
        section(t("Перерывы"), icon: "figure.cooldown") {
            ForEach(BreakKind.allCases) { kind in
                Picker(kind.title, selection: Binding(
                    get: { kind.minutes(in: settings) },
                    set: { kind.setMinutes($0, in: settings) }
                )) {
                    Text(t("Не напоминать")).tag(0)
                    ForEach(BreakKind.choices, id: \.self) { minutes in
                        Text(tf("Каждые %d мин", minutes)).tag(minutes)
                    }
                }
                .pickerStyle(.menu)
            }
            // Одной строкой, а не двумя подписями подряд: вторым видом
            // рядом с `ForEach` эта карточка роняет окно настроек целиком —
            // segfault в `ViewBuilder.buildBlock`, и `VStack` вокруг него
            // не спасает. Проверено дважды на живом окне.
            hint(t("Считается только время за компьютером. Галочка у воды спросит, сколько вы выпили."))
        }
    }

    /// Раскладка окна: донёс до чёлки — выбрал место.
    var windowSnapCard: some View {
        section(t("Раскладка окон"), icon: "rectangle.split.2x1") {
            VStack(alignment: .leading, spacing: 4) {
                Toggle(t("Раскладка окон"), isOn: settings.binding(\.windowSnapEnabled))
                hint(t("Тащите окно за заголовок к чёлке и отпустите на нужной раскладке."))
            }
            .accessibilityElement(children: .combine)
        }
    }

    var shelfSection: some View {
        Group {
            section(t("Полка"), icon: "tray.full") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Полка"), isOn: Binding(
                        get: { settings.shelfEnabled },
                        set: { settings.shelfEnabled = $0; onHotKeysChanged() }
                    ))
                    hint(t("Ведите файлы на чёлку — вырез раскроется полкой. Оттуда их вытаскивают в любое окно."))
                }
                .accessibilityElement(children: .combine)

                HStack {
                    Text(t("Открыть полку"))
                    Spacer()
                    HotKeyRecorder(label: t("Открыть полку"), spec: Binding(
                        get: { settings.shelfHotKey },
                        set: { settings.shelfHotKey = $0; onHotKeysChanged() }
                    ))
                    .frame(width: SettingsStyle.hotKeyField.width,
                                   height: SettingsStyle.hotKeyField.height)
                }
                .disabled(!settings.shelfEnabled)
            }

            section(t("Как это работает"), icon: "arrow.up.and.down.and.arrow.left.and.right") {
                // Справочная карточка: сплошной текст абзацами, а не список
                // настроек. Одной строкой — чтобы `Form` не расчерчивал абзацы
                // разделителями, будто каждый из них что-то отдельное включает.
                VStack(alignment: .leading, spacing: SettingsStyle.gap) {
                    hint(t("Файл остаётся в своей папке, пока его не вытащат."))
                    hint(t("После перезапуска полка пуста."))
                }
            }
        }
    }

    var clipboardSection: some View {
        Group {
            section(t("История буфера обмена"), icon: "doc.on.clipboard") {
                Toggle(t("История буфера обмена"), isOn: settings.binding(\.clipboardEnabled))

                HStack {
                    Text(t("Открыть историю"))
                    Spacer()
                    HotKeyRecorder(label: t("Открыть историю"), spec: Binding(
                        get: { settings.clipboardHotKey },
                        set: { settings.clipboardHotKey = $0; onHotKeysChanged() }
                    ))
                    .frame(width: SettingsStyle.hotKeyField.width,
                                   height: SettingsStyle.hotKeyField.height)
                }
                .disabled(!settings.clipboardEnabled)

                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Клавиши записей"), selection: Binding(
                        get: { settings.clipboardSlotModifiers },
                        set: { settings.clipboardSlotModifiers = $0; onHotKeysChanged() }
                    )) {
                        ForEach(ClipboardSlotModifiers.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!settings.clipboardEnabled)

                    hint(t("Цифра вставляет запись по номеру. Работает и при закрытой панели."))
                }
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Вставлять сразу"), isOn: settings.binding(\.clipboardPastes))
                        .disabled(!settings.clipboardEnabled)
                    hint(t("Выключено — запись только ложится в буфер."))
                }
                .accessibilityElement(children: .combine)
}

            section(t("Сколько хранить"), icon: "clock.arrow.circlepath") {
                Picker(t("Срок хранения"), selection: settings.binding(\.clipboardLifetimeHours)) {
                    Text(t("1 час")).tag(1)
                    Text(t("6 часов")).tag(6)
                    Text(t("сутки")).tag(24)
                    Text(t("3 дня")).tag(72)
                    Text(t("неделю")).tag(168)
                    Text(t("без ограничения")).tag(0)
                }
                .pickerStyle(.menu)

                Picker(t("Не больше записей"), selection: settings.binding(\.clipboardLimit)) {
                    ForEach([20, 30, 50], id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Text(tf("Сейчас записей: %d", clipboard.entries.count))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(t("Очистить историю"), role: .destructive) {
                        clearClipboard()
                    }
                    .disabled(clipboard.entries.isEmpty)
                }
            }

            section(t("Что не сохраняется"), icon: "lock") {
                // Справочная карточка: сплошной текст абзацами, а не список
                // настроек. Одной строкой — чтобы `Form` не расчерчивал абзацы
                // разделителями, будто каждый из них что-то отдельное включает.
                VStack(alignment: .leading, spacing: SettingsStyle.gap) {
                    hint(t("Пароли: менеджеры помечают их, и запись пропускается."))
                    hint(t("Служебные копирования, которые приложения делают для своих нужд."))
                    hint(t("Изображения крупнее шести мегабайт."))
                }
            }
        }
    }

    /// Чашка кофе. Живёт в «Инструментах»: её включают руками, как таймер
    /// и полку, — а стояла она в «Общих» просто потому, что туда попала.
    var caffeineCard: some View {
        Group {
                // Выбор срока отсюда ушёл: он появился в самой панели чашки —
                // там же, где отсчёт и кнопка «Выключить». Настройка «что
                // предлагать по умолчанию» пережила появление живого выбора
                // и стала лишней: решение одно, а мест, где его принимают,
                // стало два. Осталось то, чего в вырезе нет, — сам показ.
                section(t("Чашка кофе"), icon: "cup.and.saucer") {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(t("Чашка кофе"), isOn: settings.binding(\.caffeineEnabled))
                        hint(t("Пока включена, экран не гаснет. Срок задаётся нажатием по чашке."))
                        hint(t("Удержание не переживает перезапуск приложения."))
                    }
                    .accessibilityElement(children: .combine)
                }
        }
    }

    /// Что **вызывают руками**: буфер, полка, таймер, нагрузка, телесуфлер,
    /// чашка.
    ///
    /// Шесть карточек — не перегрузка: у каждой один-два переключателя
    /// и сочетание клавиш. Вместе выходит короче прежних «Общих», где было
    /// десять переключателей и двенадцать пояснений.
    var toolsSection: some View {
        Group {
            clipboardSection
            shelfSection
            windowSnapCard
            timerSection
            breaksCard
            monitorSection
            teleprompterSection
            caffeineCard
        }
    }
}
