import AVFoundation
import AppKit
import SwiftUI

/// Раздел настроек «Голос»: голосовой ассистент, распознавание и чтение вслух.
extension SettingsView {
    /// Модель голоса — своя, по умолчанию самая лёгкая: разбор у `VoiceModel`.
    ///
    /// Выбранная, но не скачанная модель не молчит: голос отвечает моделью
    /// разговора, и здесь это сказано прямо, с кнопкой скачать рядом.
    /// Иначе человек выбрал бы лёгкую и не понял, почему голос не ускорился.
    var voiceModelRow: some View {
        let stored = settings.voiceModel
        let wanted = ModelRef.parse(stored, fallback: settings.aiProvider)
        let isMissing = !stored.isEmpty && !models.models.isEmpty
            && VoiceModel.resolve(stored: stored, installed: models.models, fallback: settings.aiProvider) == nil

        return VStack(alignment: .leading, spacing: 4) {
            Picker(t("Модель ответа"), selection: settings.binding(\.voiceModel)) {
                Text(t("Как в разговоре")).tag("")
                ForEach(voiceModelChoices, id: \.self) { choice in
                    Text(ModelRef.parse(choice, fallback: settings.aiProvider)?.shortName ?? choice)
                        .tag(choice)
                }
            }
            .pickerStyle(.menu)
            .disabled(!settings.voiceEnabled || !settings.ollamaEnabled)
            hint(t("Голосу важнее скорость — по умолчанию самая лёгкая."))

            if isMissing, let wanted {
                Text(tf("%@ не скачана — пока отвечает модель разговора.", wanted.shortName))
                    .font(.callout)
                    .foregroundStyle(Palette.warning)
                if wanted.provider == .ollama {
                    installRow(wanted.name)
                }
            }
        }
        .onAppear { if settings.ollamaEnabled { models.refreshIfNeeded() } }
    }

    /// Что предлагать голосу: разговорные модели всех включённых провайдеров
    /// и сам выбор, даже если его нет в списке — иначе поле выглядело бы
    /// пустым, будто модель не выбрана.
    var voiceModelChoices: [String] {
        chatModelChoices(keeping: settings.voiceModel)
    }

    /// Разговорные модели всех включённых провайдеров — для голоса и сводок.
    func chatModelChoices(keeping current: String) -> [String] {
        var choices = settings.enabledProviders
            .flatMap { models.models(of: $0, kind: .chat) }
            .map(\.stored)
        if !current.isEmpty, !choices.contains(where: { RecommendedModel.same($0, current) }) {
            choices.insert(current, at: 0)
        }
        return choices
    }

    var voiceSection: some View {
        Group {
            if !settings.ollamaEnabled {
                modelRequiredCard(t("Голосовому ассистенту отвечает модель."))
            }
            section(t("Голосовой ассистент"), icon: "waveform") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Голосовой ассистент"), isOn: Binding(
                        get: { settings.voiceEnabled },
                        set: { settings.voiceEnabled = $0; onHotKeysChanged() }
                    ))
                    hint(t("Вопрос голосом, ответ вслух. Панель не раскрывается — вырез светится."))
                }
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Спросить голосом"), selection: Binding(
                        get: { settings.voiceTrigger },
                        set: { settings.voiceTrigger = $0; onHotKeysChanged() }
                    )) {
                        ForEach(VoiceTrigger.allCases) { trigger in
                            Text(trigger.title).tag(trigger)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!settings.voiceEnabled)

                    // Поле только под свой выбор: постоянно висящее, оно
                    // обещало бы второй вызов, работающий заодно с жестом.
                    if settings.voiceTrigger == .hotKey {
                        HStack {
                            Text(t("Сочетание"))
                            Spacer()
                            HotKeyRecorder(label: t("Сочетание"), spec: Binding(
                                get: { settings.voiceHotKey },
                                set: { settings.voiceHotKey = $0; onHotKeysChanged() }
                            ))
                            .frame(width: SettingsStyle.hotKeyField.width,
                                   height: SettingsStyle.hotKeyField.height)
                        }
                        .disabled(!settings.voiceEnabled)
                    }

                    hint(t("Модификатор, нажатый дважды подряд, без других клавиш между нажатиями."))
                    hint(t("«Своё сочетание» в списке меняет жест на обычные клавиши."))
                    hint(t("Нужен Универсальный доступ."))
                }
            }

            section(t("Как слушать"), icon: "mic") {
                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Язык распознавания"), selection: Binding(
                        get: { settings.voiceLanguage },
                        set: { settings.voiceLanguage = $0 }
                    )) {
                        Text(t("Как в интерфейсе")).tag(Language?.none)
                        ForEach(Language.allCases) { language in
                            Text(language.title).tag(Language?.some(language))
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!settings.voiceEnabled)
                    hint(t("Можно говорить не на языке интерфейса."))
                }
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Пауза до конца фразы"), selection: settings.binding(\.voiceSilenceTenths)) {
                        ForEach([8, 12, 15, 20, 30], id: \.self) { tenths in
                            Text(tf("%@ с", Self.seconds(tenths))).tag(tenths)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!settings.voiceEnabled)
                    hint(t("Сколько молчания считается концом вопроса."))
                }
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 4) {
                    Toggle(t("Ждать ответа после сказанного"), isOn: settings.binding(\.voiceKeepsListening))
                        .disabled(!settings.voiceEnabled)
                    hint(t("Дочитав ответ, вырез слушает снова. Молчание гасит заход."))
                }
                .accessibilityElement(children: .combine)

                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Заметок в голосовой вопрос"), selection: settings.binding(\.voiceNotesContextLimit)) {
                        ForEach([2_000, 4_000, 6_000, 12_000, 24_000], id: \.self) { value in
                            Text(tf("%d тыс. знаков", value / 1_000)).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!settings.voiceEnabled || !settings.notesEnabled)
                    hint(t("Меньше, чем в тексте: голосового ответа ждут ушами."))
                }
                .accessibilityElement(children: .combine)
            }

            section(t("Как отвечать"), icon: "speaker.wave.2") {
                voiceModelRow

                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Голос"), selection: Binding(
                        get: { settings.voiceIdentifier },
                        set: { settings.voiceIdentifier = $0 }
                    )) {
                        Text(t("Лучший из установленных")).tag(String?.none)
                        ForEach(voices, id: \.identifier) { voice in
                            Text(SpeechSpeaker.title(for: voice))
                                .tag(String?.some(voice.identifier))
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!settings.voiceEnabled)

                    HStack {
                        Spacer()
                        Button(t("Прослушать")) { onPreviewVoice() }
                            .disabled(!settings.voiceEnabled)
                    }
                    // Выбирать голос глазами нельзя: имена у них случайные —
                    // системный премиальный русский зовётся «Голос 2»,
                    // и по названию не понять о нём ничего. Слышно только
                    // на слух, значит слушать надо прямо здесь.
                    hint(t("Новые голоса — в «Универсальный доступ» → «Чтение вслух». Компактные звучат роботом."))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Picker(t("Скорость чтения"), selection: settings.binding(\.voiceRateStep)) {
                        ForEach(-SpeechSpeaker.rateSteps...SpeechSpeaker.rateSteps, id: \.self) { step in
                            Text(Self.rateTitle(step)).tag(step)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(!settings.voiceEnabled)
                }
            }
        }
    }

    /// Голоса, установленные для языка, на котором будут отвечать.
    var voices: [AVSpeechSynthesisVoice] {
        SpeechSpeaker.voices(for: settings.voiceLanguage ?? Localization.shared.resolved)
    }

    /// Скорость подписью, а не числом: «−2» человеку ничего не говорит.
    static func rateTitle(_ step: Int) -> String {
        switch step {
        case 0: return t("Обычная")
        case ..<0: return tf("Медленнее на %d", -step)
        default: return tf("Быстрее на %d", step)
        }
    }

    /// Десятые доли секунды словами: «1,5» вместо «15».
    static func seconds(_ tenths: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Localization.shared.resolved.locale
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: Double(tenths) / 10)) ?? "\(tenths)"
    }
}
