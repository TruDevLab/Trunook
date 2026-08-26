import AppKit
import Foundation
import Testing
@testable import Trunook

/// Жест вызова: модификатор, нажатый дважды.
///
/// Проверяется подробнее прочего, и вот почему: **ложное срабатывание здесь
/// хуже несработавшего**. Не сработавший жест человек повторит, а сработавший
/// посреди работы откроет микрофон, о котором не просили, — и хорошо, если
/// это заметят.
@Suite("Двойное нажатие модификатора")
struct DoubleTapModifierTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    /// Один тап: нажали и отпустили.
    private func tap(
        _ detector: DoubleTapModifier,
        _ flag: NSEvent.ModifierFlags,
        down: TimeInterval,
        up: TimeInterval
    ) -> Bool {
        _ = detector.flagsChanged(to: flag, at: start.addingTimeInterval(down))
        return detector.flagsChanged(to: [], at: start.addingTimeInterval(up))
    }

    @Test("Два коротких нажатия подряд — жест")
    func двойноеСрабатывает() {
        let detector = DoubleTapModifier(flag: .control)
        #expect(tap(detector, .control, down: 0, up: 0.05) == false)
        #expect(tap(detector, .control, down: 0.15, up: 0.2) == true)
    }

    @Test("Одиночное нажатие не срабатывает")
    func одиночноеМолчит() {
        let detector = DoubleTapModifier(flag: .control)
        #expect(tap(detector, .control, down: 0, up: 0.05) == false)
    }

    /// Окно нужно, чтобы два не связанных между собой нажатия модификатора
    /// не склеивались в жест: за секунду человек успевает передумать.
    @Test("Второй тап за окном не считается")
    func окноИстекает() {
        let detector = DoubleTapModifier(flag: .control)
        #expect(tap(detector, .control, down: 0, up: 0.05) == false)
        let late = DoubleTapModifier.window + 0.2
        #expect(tap(detector, .control, down: late, up: late + 0.05) == false)
    }

    /// Самая важная проверка. ⌃C — это ⌃ вниз, C, ⌃ вверх. Скопировать
    /// два раза подряд — обычное дело, и без учёта нажатой клавиши это
    /// звало бы ассистента.
    @Test("Клавиша между нажатиями отменяет счёт")
    func чужаяКлавишаСбрасывает() {
        let detector = DoubleTapModifier(flag: .control)
        _ = detector.flagsChanged(to: .control, at: start)
        detector.otherInput() // нажали C
        #expect(detector.flagsChanged(to: [], at: start.addingTimeInterval(0.05)) == false)

        _ = detector.flagsChanged(to: .control, at: start.addingTimeInterval(0.15))
        detector.otherInput()
        #expect(detector.flagsChanged(to: [], at: start.addingTimeInterval(0.2)) == false)
    }

    /// ⌃⌥ — набор сочетания, а не жест. Причём испортить должно и уже
    /// начатый счёт: человек, взявшийся набирать сочетание, жеста не делал.
    @Test("Другой модификатор сверху отменяет счёт")
    func чужойМодификаторСбрасывает() {
        let detector = DoubleTapModifier(flag: .control)
        #expect(tap(detector, .control, down: 0, up: 0.05) == false)

        _ = detector.flagsChanged(to: [.control], at: start.addingTimeInterval(0.1))
        _ = detector.flagsChanged(to: [.control, .option], at: start.addingTimeInterval(0.12))
        #expect(detector.flagsChanged(to: [], at: start.addingTimeInterval(0.15)) == false)
    }

    /// Зажатый модификатор — это навигация или перетаскивание.
    @Test("Удержание не считается тапом")
    func удержаниеНеТап() {
        let detector = DoubleTapModifier(flag: .option)
        let long = DoubleTapModifier.maxHold + 0.2
        #expect(tap(detector, .option, down: 0, up: long) == false)
        // И следующее короткое нажатие тоже не должно сработать: первого
        // тапа не было, считать не с чем.
        #expect(tap(detector, .option, down: long + 0.1, up: long + 0.15) == false)
    }

    /// Служебные биты приходят вместе с настоящими: Caps Lock, признак
    /// цифровой клавиатуры, `.function` от любой стрелки. Без их чистки
    /// «нажат ровно наш модификатор» не сошлось бы никогда.
    @Test("Служебные биты не мешают")
    func служебныеБитыИгнорируются() {
        let detector = DoubleTapModifier(flag: .control)
        let noisy: NSEvent.ModifierFlags = [.control, .capsLock, .function]
        #expect(tap(detector, noisy, down: 0, up: 0.05) == false)
        #expect(tap(detector, noisy, down: 0.15, up: 0.2) == true)
    }

    @Test("Свой модификатор у каждого вызова")
    func свойМодификатор() {
        let detector = DoubleTapModifier(flag: .option)
        // Дважды ⌃ не должно звать того, кто ждёт ⌥.
        #expect(tap(detector, .control, down: 0, up: 0.05) == false)
        #expect(tap(detector, .control, down: 0.15, up: 0.2) == false)
    }

    @Test("Сброс забывает начатое")
    func сбросЗабывает() {
        let detector = DoubleTapModifier(flag: .control)
        #expect(tap(detector, .control, down: 0, up: 0.05) == false)
        detector.reset()
        #expect(tap(detector, .control, down: 0.15, up: 0.2) == false)
    }
}

@Suite("Вызов голоса")
struct VoiceTriggerTests {
    /// ⇧ в списке быть не должно: две заглавные подряд — обычный набор,
    /// а не жест, и «ББ» в начале слова звало бы ассистента.
    @Test("Двойная ⇧ не предлагается")
    func сдвигНеПредлагается() {
        for trigger in VoiceTrigger.allCases {
            #expect(trigger.flag != .shift, "⇧ попала в список вызовов")
        }
    }

    @Test("Выключенный вызов не даёт модификатора")
    func выключенныйПуст() {
        #expect(VoiceTrigger.off.flag == nil)
        #expect(VoiceTrigger.control.flag == .control)
        #expect(VoiceTrigger.option.flag == .option)
    }

    /// Свечение уходит за края полосы, а окно обрезает всё, что не влезло:
    /// по краю пошла бы ровная линия среза вместо угасания. Ловится это
    /// только снимком — значит должно ловиться расчётом.
    @Test("Окно вмещает свечение целиком")
    func окноВмещаетСвечение() {
        let metrics = NotchMetrics(notchWidth: 185, notchHeight: 32)
        let glowing = VoiceChipView.width(metrics: metrics) + 2 * VoiceGlow.spread
        #expect(
            metrics.windowSize.width >= glowing,
            "свечение \(glowing) шире окна \(metrics.windowSize.width)"
        )
        #expect(
            metrics.windowSize.height >= metrics.notchHeight + 2 * VoiceGlow.spread,
            "свечение выше окна"
        )
        #expect(VoiceGlow.spread > 0)
    }

    /// Слои идут от плотного у кромки к прозрачному по краю — иначе спада
    /// не получится, и свечение прочтётся ободком, а не светом.
    @Test("Слои свечения угасают наружу")
    func слоиУгасают() {
        let layers = VoiceGlow.layers
        #expect(layers.count >= 3)
        for (previous, next) in zip(layers, layers.dropFirst()) {
            #expect(next.radius > previous.radius, "слой не расходится шире прежнего")
            #expect(next.opacity < previous.opacity, "слой не бледнее прежнего")
        }
        // Вёрстка выписывает тени подряд по номерам — значит слоёв должно
        // быть ровно столько, сколько она перечисляет.
        #expect(layers.count == 4)
    }

    /// До первого слова ждём дольше, чем между фразами: человеку надо
    /// убедиться, что вызов сработал, и собраться с мыслью.
    @Test("Первого слова ждём дольше, чем паузы в речи")
    func первогоСловаЖдёмДольше() {
        for silence in [0.8, 1.5, 3.0] {
            let lead = SpeechListener.leadIn(for: silence)
            #expect(lead > silence, "ожидание \(lead) не дольше паузы \(silence)")
        }
        // И не меньше пяти секунд даже при самой короткой паузе.
        #expect(SpeechListener.leadIn(for: 0.5) >= 5)
    }

    @Test("У каждого вызова своя подпись")
    func подписиРазличаются() {
        let titles = Set(VoiceTrigger.allCases.map(\.title))
        #expect(titles.count == VoiceTrigger.allCases.count)
        for trigger in VoiceTrigger.allCases {
            #expect(!trigger.title.isEmpty)
        }
    }
}

/// Нарезка потока на то, что уже можно читать вслух.
@Suite("Озвучка ответа")
struct SpeechChunkerTests {
    /// Пока поток идёт, хвост без точки может ещё дописаться: прочитать его
    /// сейчас значило бы произнести полфразы и потом начать её заново.
    @Test("Незаконченный хвост ждёт")
    func хвостЖдёт() {
        // Предложение достаточной длины уходит в озвучку, а начатое
        // следующее ждёт своей точки.
        let done = "Билеты до Владивостока уже куплены и лежат в почте."
        #expect(SpeechChunker.complete(in: done + " Смета", isFinal: false) == done)
        #expect(SpeechChunker.complete(in: "Совсем без точки", isFinal: false) == "")
    }

    @Test("Законченный поток читается целиком")
    func потокКончился() {
        #expect(SpeechChunker.complete(in: "Совсем без точки", isFinal: true) == "Совсем без точки")
        #expect(SpeechChunker.complete(in: "", isFinal: true) == "")
    }

    /// Двоеточие концом куска быть не должно. Оно тут побывало — казалось,
    /// что так первые слова зазвучат раньше, — и на слух вышло наоборот:
    /// каждый кусок читается отдельной репликой, интонация начинается заново,
    /// и фраза звучит двумя огрызками.
    @Test("Фраза не рвётся по двоеточию")
    func двоеточиеНеРвёт() {
        let text = "Коротко: билеты куплены, смета обсуждается, отпуск близко"
        #expect(SpeechChunker.complete(in: text, isFinal: false) == "")
    }

    /// «Да.» отдельной репликой звучит обрывком: синтезатор произносит его
    /// с законченной интонацией и умолкает.
    @Test("Слишком короткий кусок ждёт продолжения")
    func короткийКусокЖдёт() {
        #expect(SpeechChunker.complete(in: "Да.", isFinal: false) == "")
        // А когда поток кончился — читаем как есть: продолжения не будет.
        #expect(SpeechChunker.complete(in: "Да.", isFinal: true) == "Да.")

        let long = "Билеты куплены, смета обсуждается, а отпуск уже совсем близко."
        #expect(SpeechChunker.complete(in: long, isFinal: false) == long)
    }

    /// Шкала громкости — единственное, что отвечает на «слышат ли меня».
    /// Молчащая на речи или упёртая в потолок на шёпоте, она отвечает
    /// неверно.
    /// Первое, что слышно в кривом ответе: синтезатор честно выговаривает
    /// название маркера списка. Разметку снимает `MarkdownRender`, а маркер
    /// он **оставляет намеренно** — глазу тот нужен.
    @Test("Маркеры списка вслух не читаются")
    func маркерыНеЧитаются() {
        #expect(SpokenText.clean("• Купить билеты") == "Купить билеты")
        #expect(SpokenText.clean("- Раз\n• Два") == "Раз\nДва")
        // Номер у пункта значащий — «во-первых» слышно именно из него.
        #expect(SpokenText.clean("1. Раз").hasPrefix("1."))
    }

    /// Ссылку вслух не воспроизвести: выйдет минута по буквам и косым
    /// чертам. Но и молча выбросить нельзя — фраза осталась бы без члена
    /// предложения.
    @Test("Адрес заменяется словом")
    func адресЗаменяется() {
        let spoken = SpokenText.clean("Подробности на https://example.com/very/long/path тут")
        #expect(!spoken.contains("https"))
        #expect(!spoken.contains("example"))
        #expect(spoken.contains(t("ссылка")))
    }

    @Test("Эмодзи не проговариваются")
    func эмодзиУбираются() {
        let spoken = SpokenText.clean("Готово 🎉 можно ехать")
        #expect(!spoken.contains("🎉"))
        #expect(spoken.contains("Готово"))
        #expect(spoken.contains("можно ехать"))
    }

    @Test("Громкость растёт вместе со звуком")
    func громкостьРастёт() {
        let quiet = SpeechLevel.normalize(rms: 0.001)
        let speech = SpeechLevel.normalize(rms: 0.05)
        let loud = SpeechLevel.normalize(rms: 0.5)
        #expect(quiet < speech, "тишина \(quiet) не тише речи \(speech)")
        #expect(speech < loud, "речь \(speech) не тише крика \(loud)")
        #expect(quiet >= 0 && loud <= 1)
    }

    @Test("Сглаживание тянется к новому значению, но не прыгает")
    func сглаживание() {
        let stepped = SpeechLevel.smooth(previous: 0, next: 1)
        #expect(stepped > 0 && stepped < 1)
        // Повторяясь, значение всё же доходит до цели: шкала не должна
        // застревать на полпути.
        var value: Double = 0
        for _ in 0..<20 { value = SpeechLevel.smooth(previous: value, next: 1) }
        #expect(value > 0.95)
    }

    /// Одного имени в списке мало: системные имена ничего не говорят.
    /// Русский нейронный голос зовётся «Голос 2», и по названию его
    /// не отличить от компактной Milena — а это и есть разница между
    /// «человек говорит» и «робот читает».
    @Test("Имя голоса в списке помечено качеством")
    func имяГолосаСКачеством() {
        for language in Language.allCases {
            for voice in SpeechSpeaker.voices(for: language) {
                let title = SpeechSpeaker.title(for: voice)
                #expect(title.contains(voice.name), "в подписи «\(title)» нет имени голоса")
                #expect(title.count > voice.name.count, "к имени «\(voice.name)» не добавлено качество")
            }
        }
    }

    /// Лучший голос — это голос наибольшего качества, а не первый попавшийся
    /// в системном порядке. Разница между компактным и нейронным — это
    /// разница между «робот читает» и «человек говорит», и по умолчанию
    /// должен доставаться второй.
    @Test("По умолчанию берётся лучший из установленных")
    func берётсяЛучший() {
        for language in Language.allCases {
            let voices = SpeechSpeaker.voices(for: language)
            guard let best = SpeechSpeaker.best(for: language) else { continue }
            let top = voices.map(\.quality.rawValue).max() ?? 0
            #expect(
                best.quality.rawValue == top,
                "для \(language.rawValue) выбран \(best.name) качества \(best.quality.rawValue), а есть \(top)"
            )
        }
    }

    /// Заданный руками голос важнее любого расчёта: человек выбрал сам.
    @Test("Выбранный руками голос перебивает лучший")
    func свойГолосВажнее() {
        let voices = SpeechSpeaker.voices(for: .ru)
        // Берём заведомо не лучший — последний в порядке убывания качества.
        guard let worst = voices.last, voices.count > 1 else { return }
        let chosen = SpeechSpeaker.voice(language: .ru, identifier: worst.identifier)
        #expect(chosen?.identifier == worst.identifier)
    }

    /// Скорость ступенями от обычной: у `AVSpeechUtterance` шкала своя
    /// и непрозрачная, и «0,5», записанное числом, означало бы разное
    /// в разных версиях системы.
    @Test("Скорость растёт по ступеням")
    func скоростьПоСтупеням() {
        let slow = SpeechSpeaker.rate(forStep: -SpeechSpeaker.rateSteps)
        let normal = SpeechSpeaker.rate(forStep: 0)
        let fast = SpeechSpeaker.rate(forStep: SpeechSpeaker.rateSteps)
        #expect(slow < normal)
        #expect(normal < fast)
    }
}

/// Лента переписки в панели и её высота.
@Suite("Лента разговора")
struct TranscriptTests {
    private let notchWidth: CGFloat = 185
    private let metrics = NotchMetrics(notchWidth: 185, notchHeight: 32)

    private func reply(_ role: AssistantSession.Reply.Role, _ text: String, _ id: Int) -> AssistantSession.Reply {
        AssistantSession.Reply(id: id, role: role, text: text)
    }

    @Test("Лента длиннее одной реплики выше")
    func лентаРастёт() {
        let one = AssistantPanel.bodyHeight(
            transcript: [reply(.user, "вопрос", 0)],
            isStreaming: false,
            notchWidth: notchWidth
        )
        let three = AssistantPanel.bodyHeight(
            transcript: [
                reply(.user, "вопрос", 0),
                reply(.assistant, "ответ", 1),
                reply(.user, "ещё вопрос", 2),
            ],
            isStreaming: false,
            notchWidth: notchWidth
        )
        #expect(three > one)
    }

    /// Панель, растущая без предела, обрезалась бы краем окна — и увидеть
    /// это можно было бы только снимком.
    @Test("Лента упирается в потолок и прокручивается")
    func лентаПрокручивается() {
        let long = (0..<40).map { reply($0.isMultiple(of: 2) ? .user : .assistant, "реплика номер \($0)", $0) }
        let height = AssistantPanel.bodyHeight(
            transcript: long,
            isStreaming: false,
            notchWidth: notchWidth
        )
        #expect(height == AssistantPanel.maxBodyHeight)
        #expect(metrics.windowSize.height >= AssistantPanel.height(
            notchHeight: 32,
            notchWidth: notchWidth,
            transcript: long,
            isStreaming: false
        ))
    }

    /// Пока идёт поток, высота держится потолком: панель, подраставшая
    /// на каждой новой строке, дёргала бы вырез десяток раз за ответ.
    @Test("Во время потока высота не пляшет")
    func потокДержитПотолок() {
        let height = AssistantPanel.bodyHeight(
            transcript: [reply(.assistant, "нача", 0)],
            isStreaming: true,
            notchWidth: notchWidth
        )
        #expect(height == AssistantPanel.maxBodyHeight)
    }

    /// Реплика человека лежит в капсуле у правого края и во всю ширину
    /// не растягивается — значит и место под неё меряется своё.
    @Test("Своя реплика меряется по своей ширине")
    func свояРепликаУже() {
        let text = String(repeating: "слово ", count: 30)
        let wide = AssistantPanel.userReplyHeight(text, available: 400)
        let narrow = AssistantPanel.userReplyHeight(
            text,
            available: 400 - AssistantPanel.userReplyInset
        )
        #expect(narrow >= wide)
        #expect(AssistantPanel.userReplyInset > 0)

        // Поля капсулы — это высота сверх текста. Без них лента съезжает
        // вверх и обрезается снизу; так уже вышло на первом же снимке.
        let bare = AssistantPanel.answerReplyHeight("слово", available: 400)
        let capsule = AssistantPanel.userReplyHeight("слово", available: 400)
        #expect(capsule > bare, "капсула \(capsule) не выше голого текста \(bare)")

        // Пункту списка достаётся меньше ширины — колонку занимает маркер.
        // Не учесть это значило бы недосчитать строку ровно там, где текст
        // и переносится.
        let long = String(repeating: "длинное слово ", count: 6)
        let paragraph = AssistantPanel.answerReplyHeight(long, available: 200)
        let item = AssistantPanel.answerReplyHeight("- " + long, available: 200)
        #expect(item >= paragraph)
    }
}
