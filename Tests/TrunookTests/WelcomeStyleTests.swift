import Testing
import CoreGraphics
import Foundation
@testable import Trunook

@Suite("Лестница кеглей знакомства")
struct WelcomeStyleTests {
    /// Ступени обязаны различаться, иначе лестницы нет.
    ///
    /// До `WelcomeStyle` кегли стояли числами по месту, и близнецы заводились
    /// сами собой: заголовок карточки был набран и тринадцатью, и тринадцатью
    /// с половиной — на глаз одно и то же, в коде два разных числа. Проверка
    /// ловит обратный случай: ступень, схлопнувшуюся с соседней при правке.
    @Test("Каждая ступень крупнее следующей")
    func лестницаУбывает() {
        let ladder: [(String, CGFloat)] = [
            ("hero", WelcomeStyle.hero),
            ("finale", WelcomeStyle.finale),
            ("chapter", WelcomeStyle.chapter),
            ("deck", WelcomeStyle.deck),
            ("title", WelcomeStyle.title),
            ("body", WelcomeStyle.body),
            ("detail", WelcomeStyle.detail),
            ("caption", WelcomeStyle.caption),
            ("micro", WelcomeStyle.micro),
        ]

        for (previous, next) in zip(ladder, ladder.dropFirst()) {
            #expect(
                previous.1 > next.1,
                "\(previous.0) \(previous.1) не крупнее \(next.0) \(next.1)"
            )
        }
    }

    /// Окно растёт тем же множителем, что и текст в нём.
    ///
    /// Порознь их не масштабировать — то же правило, что в `NotchStyle`:
    /// строка, выросшая в раме прежнего размера, об эту раму и обрежется.
    /// Раньше рама была выписана числом — 780 на 700, — и настройка размера
    /// текста до окна знакомства не доходила вовсе.
    @Test("Окно и текст растут одним множителем")
    func окноРастётВместеСТекстом() {
        let byFont = WelcomeStyle.title / 13
        let byWidth = WelcomeStyle.windowSize.width / WelcomeStyle.baseWindow.width
        let byHeight = WelcomeStyle.windowSize.height / WelcomeStyle.baseWindow.height

        #expect(abs(byFont - byWidth) < 0.05, "ширина окна растёт не как текст")
        #expect(abs(byFont - byHeight) < 0.05, "высота окна растёт не как текст")
    }

    /// Окну знакомства потолок выреза не указ.
    ///
    /// Панель прибита к верхней кромке экрана, поэтому `NotchStyle` ограничен
    /// полутора. Окно — обычное, растёт и тянется мышью, — и обязано отдавать
    /// все двести процентов, которых требует критерий.
    @Test("Масштаб окна не срезан потолком выреза")
    func потолкаВырезаНет() {
        let defaults = UserDefaults(suiteName: "trunook-tests-\(UUID().uuidString)")!
        let settings = Settings(defaults: defaults)
        settings.textScale = Settings.textScales.max() ?? 200

        // Как и в проверке выреза, общие настройки отсюда не подменить,
        // поэтому смотрим на само правило: у окна деления на потолок нет.
        #expect(
            WelcomeStyle.font(100) == 100 * WelcomeStyle.textScale,
            "масштаб окна где-то ограничили"
        )
        #expect(Settings.textScales.max() == 200, "верхняя ступень настройки уехала")
    }
}

@Suite("Лестница кеглей выреза")
struct NotchStyleTests {
    /// Ступени обязаны различаться на **каждой** настройке размера, а не
    /// только на ста процентах.
    ///
    /// Округление кегля стоило целой ступени и ловилось только так: на ста
    /// процентах шапка и строка давали 11 и 12, а на ста двадцати пяти —
    /// четырнадцать обе. Проверка на одном масштабе прошла бы и ничего
    /// не заметила.
    ///
    /// Множитель здесь свой, а не из общих настроек: подменить `Settings.shared`
    /// из теста нечем, а проверять надо само правило — что кегли не
    /// округляются, — а не то, что стоит у человека в настройках.
    @Test("Кегли не схлопываются ни на одной ступени настройки")
    func лестницаНеСхлопывается() {
        // Вырез настройку не читает — но лестница обязана держаться
        // при любом множителе: если масштабирование когда-нибудь вернут,
        // ошибка не должна вернуться вместе с ним.
        for percent in Settings.textScales {
            let scale = CGFloat(percent) / 100
            let ladder: [(String, CGFloat)] = [
                ("строка", 11.5 * scale),
                ("шапка", 11 * scale),
                ("подпись", 9.5 * scale),
                ("подсказка", 8.5 * scale),
            ]

            for (previous, next) in zip(ladder, ladder.dropFirst()) {
                #expect(
                    previous.1 > next.1,
                    "\(percent)%: \(previous.0) \(previous.1) не крупнее \(next.0) \(next.1)"
                )
            }
        }
    }

    /// Кегль не округляется, размер — округляется.
    ///
    /// Половина пункта в букве законна и нужна: на ней стоят две ступени
    /// из четырёх. Половина точки в раме — размытый край, и там округление
    /// на месте.
    @Test("Буквы не округляются, рамы округляются")
    func буквыИРамыСчитаютсяПоРазному() {
        #expect(NotchStyle.font(11.5) == 11.5 * NotchStyle.textScale)
        #expect(NotchStyle.scaled(11.5) == (11.5 * NotchStyle.textScale).rounded())
    }
}

@Suite("Шкала окна настроек")
struct SettingsStyleTests {
    /// Кегль и подогнанный под него размер растут одним множителем.
    ///
    /// Проверка появилась после того, как правило нарушили в третий раз:
    /// в `SettingsStyle` кегль значка в полосе разделов шёл через `font`,
    /// а сторона плитки под ним стояла числом — на ста пятидесяти процентах
    /// значок вылезал за собственную подложку. Следом обнаружилось то же
    /// с зазором между плиткой и названием раздела.
    ///
    /// Отношение, а не абсолютные значения: настройку из теста не подменить,
    /// а проверять надо связь между двумя величинами, а не их размер.
    @Test("Плитка значка растёт как значок в ней")
    func плиткаРастётКакЗначок() {
        let byGlyph = SettingsStyle.font(10) / 10
        let byTile = SettingsStyle.glyphSide / 20
        #expect(abs(byGlyph - byTile) < 0.06, "плитка растёт не как значок в ней")
    }

    /// Окно растёт вместе с текстом — иначе выросшие строки обрежутся рамой.
    @Test("Окно настроек растёт как текст в нём")
    func окноРастётКакТекст() {
        let byFont = SettingsStyle.font(13) / 13
        let byWidth = SettingsStyle.windowSize.width / SettingsStyle.baseWindow.width
        #expect(abs(byFont - byWidth) < 0.05, "ширина окна растёт не как текст")
    }

    /// Поля, подогнанные под кегль, — тем же множителем.
    @Test("Поля растут как кегль")
    func поляРастутКакКегль() {
        let byFont = SettingsStyle.font(13) / 13
        for (name, value, base) in [
            ("поле сочетания", SettingsStyle.hotKeyField.width, CGFloat(140)),
            ("список выбора", SettingsStyle.pickerWidth, CGFloat(300)),
            ("поиск города", SettingsStyle.searchFieldWidth, CGFloat(260)),
        ] {
            #expect(abs(byFont - value / base) < 0.05, "\(name) растёт не как кегль")
        }
    }
}
