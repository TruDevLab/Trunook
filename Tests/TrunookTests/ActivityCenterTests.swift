import Foundation
import Testing
@testable import Trunook

@Suite("Плашки событий")
struct ActivityCenterTests {
    /// Свои настройки, а не общие: тест не должен переписывать выбранное
    /// человеком.
    private func center(hold: Int? = nil) -> ActivityCenter {
        let defaults = UserDefaults(suiteName: "trunook-tests-\(UUID().uuidString)")!
        let settings = Settings(defaults: defaults)
        if let hold { settings.activityHold = hold }
        return ActivityCenter(settings: settings)
    }

    /// Скопированная запись для плашки.
    private static func copied(_ text: String) -> ClipboardEntry {
        ClipboardEntry(id: 1, kind: .text, text: text, copiedAt: Date())
    }

    /// Сроки плашек короткие и подобраны под того, кто в этот момент смотрит
    /// на экран. Кому их мало, тот растягивает — иначе продлить было нечем:
    /// таймер одноразовый и ни на что не смотрит.
    @Test("Настройка растягивает срок плашки")
    func срокРастягивается() {
        let activity = Activity(kind: .trackChanged)
        let base = activity.duration

        #expect(center(hold: 1).hold(for: activity) == base)
        #expect(center(hold: 3).hold(for: activity) == base * 3)
        #expect(center(hold: 10).hold(for: activity) == base * 10)
    }

    /// Ноль — «пока не уберу». Плашку в этом случае убирает наведение
    /// на вырез, так что навсегда она не запирается.
    @Test("Ноль означает «без срока»")
    func нольБезСрока() {
        #expect(!center(hold: 0).hold(for: Activity(kind: .trackChanged)).isFinite)
    }

    /// Плашка полки и без настройки висит бессрочно — растягивать
    /// бесконечность нечем, и умножение не должно превратить её в число.
    @Test("Бессрочная плашка остаётся бессрочной при любой настройке")
    func бессрочнаяНеМеняется() {
        let shelf = Activity(kind: .shelf(count: 2))
        for hold in Settings.activityHolds {
            #expect(!center(hold: hold).hold(for: shelf).isFinite,
                    "при настройке \(hold) полка получила срок")
        }
    }

    /// Десятка в списке не для ровного счёта: столько требует критерий
    /// доступности от настройки, которая заменяет предупреждение о том,
    /// что время вышло.
    @Test("Среди вариантов есть десятикратный и «пока не уберу»")
    func вариантыСроков() {
        #expect(Settings.activityHolds.contains(10), "нет десятикратного продления")
        #expect(Settings.activityHolds.contains(0), "нет варианта «пока не уберу»")
        #expect(Settings.activityHolds.first == 1, "обычный срок должен идти первым")

        let titles = Settings.activityHolds.map(SettingsView.activityHoldTitle)
        #expect(Set(titles).count == titles.count, "подписи повторяются: \(titles)")
        #expect(titles.allSatisfy { !$0.isEmpty })
    }

    @Test("Менее важное событие не вытесняет более важное")
    func приоритетВытеснения() {
        let center = ActivityCenter()
        center.present(.command(text: "идёт", state: .running))
        center.present(.trackChanged)
        // Смена трека — приоритет 1, отклик на команду — 5.
        if case .command = center.current?.kind {} else {
            Issue.record("плашку команды вытеснила смена трека")
        }
    }

    @Test("Равное по важности заменяет показанное")
    func равноеЗаменяет() {
        let center = ActivityCenter()
        center.present(.lowBattery(percentage: 20))
        center.present(.clipboard(entry: Self.copied("текст")))
        if case .clipboard = center.current?.kind {} else {
            Issue.record("плашка буфера не заменила равную по важности")
        }
    }

    @Test("Плашка полки висит без срока, остальные — со сроком")
    func срокПлашки() {
        #expect(Activity(kind: .shelf(count: 2)).duration.isInfinite)
        #expect(Activity(kind: .trackChanged).duration.isFinite)
    }

    @Test("По плашкам буфера и полки можно нажать, по прочим нельзя")
    func интерактивность() {
        #expect(Activity(kind: .shelf(count: 1)).isInteractive)
        #expect(Activity(kind: .clipboard(entry: Self.copied("т"))).isInteractive)
        #expect(!Activity(kind: .trackChanged).isInteractive)
    }

    @Test("Готовое обновление заменяет свою «Проверяю…», хоть та и важнее")
    func заменаСвоейПлашки() {
        let center = ActivityCenter()
        center.present(.command(text: "Найдена версия 0.23.0 — скачиваю…", state: .running))
        // Обычным путём обновление (приоритет 2) под командой (5) отбрасывалось.
        center.present(.update(version: "0.23.0"))
        if case .update = center.current?.kind {
            Issue.record("обычный путь не должен перебивать более важное")
        }
        center.present(.update(version: "0.23.0")) { kind in
            if case .command(_, .running) = kind { return true }
            return false
        }
        if case .update = center.current?.kind {} else {
            Issue.record("готовое обновление не заменило свою плашку «скачиваю…»")
        }
    }

    @Test("Чужую плашку путь замены не перебивает")
    func чужуюНеЗаменяет() {
        let center = ActivityCenter()
        center.present(.command(text: "Перевести на русский", state: .running))
        center.present(.update(version: "0.23.0")) { _ in false }
        if case .command = center.current?.kind {} else {
            Issue.record("чужая команда вытеснена")
        }
    }

    @Test("Под курсором плашка не истекает, после ухода висит не меньше запаса")
    func паузаПодКурсором() async throws {
        let center = center()
        center.present(.trackChanged)   // 4 секунды
        center.hold(true)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(center.current != nil)
        // Повторная пауза не сбрасывает остаток, а отпускание без паузы
        // ничего не ломает.
        center.hold(true)
        center.hold(false)
        center.hold(false)
        #expect(center.current != nil)
        #expect(ActivityCenter.graceAfterHover >= 3)
    }

    @Test("Досрочное снятие очищает плашку")
    func снятие() {
        let center = ActivityCenter()
        center.present(.trackChanged)
        center.dismiss()
        #expect(center.current == nil)
    }
}


@Suite("Поля плашки события")
struct ActivityLayoutPaddingTests {
    /// Форма плашки уводит верхние уголки наружу, и чёрное тело у́же рамки
    /// на вогнутое плечо с каждой стороны. Поле, отмеренное от рамки, на этом
    /// плече и кончается: двадцать точек слева превращались в восемь,
    /// четырнадцать справа — в два, и значок с числом липли к краям.
    ///
    /// Ровно ту же ошибку ловили в панели ответа модели и в таймере — плашку
    /// тогда не тронули. Тест держит правило: поле отмеряется от тела.
    @Test("Поля отмерены от чёрного тела, а не от рамки")
    func поляОтТела() {
        #expect(ActivityLayout.leadingPadding > NotchStyle.shoulderInset)
        #expect(ActivityLayout.trailingPadding > NotchStyle.shoulderInset)
        // От тела остаётся столько, чтобы значок не касался кромки.
        #expect(ActivityLayout.leadingPadding - NotchStyle.shoulderInset >= 10)
        #expect(ActivityLayout.trailingPadding - NotchStyle.shoulderInset >= 8)
    }

    /// Ширина считается по тем же полям, что и рисуется. Разойдись они —
    /// текст обрезался бы ровно на столько, на сколько поля разошлись.
    @Test("Ширина плашки растёт вместе с полями")
    func ширинаУчитываетПоля() {
        let layout = ActivityLayout(
            text: "Низкий заряд",
            trailing: "20%",
            minimumWidth: 201
        )
        let fixed = ActivityLayout.leadingPadding + ActivityLayout.trailingPadding
            + ActivityLayout.iconSize + ActivityLayout.spacing
        #expect(layout.panelWidth - layout.textWidth >= fixed)
    }
}

@Suite("Мини-вид при наведении")
struct PreviewJoinTests {
    private static func event(link: URL?) -> CalendarItem {
        CalendarItem(
            id: "1", title: "Созвон", start: Date(), end: nil, isAllDay: false,
            source: .event, link: link.map { MeetingLink(url: $0, provider: .telemost) },
            colorComponents: nil
        )
    }

    @Test("У встречи со ссылкой в мини-виде есть «Подключиться»")
    func кнопкаЕсть() {
        let url = URL(string: "https://telemost.yandex.ru/j/123")!
        #expect(PreviewPanel.joinLink(track: nil, event: Self.event(link: url)) == url)
        // Место под капсулу отмеряется: иначе она обрезала бы название.
        let metrics = NotchMetrics(notchWidth: 185, notchHeight: 32)
        let with = PreviewPanel.layout(track: nil, event: Self.event(link: url), metrics: metrics)
        let without = PreviewPanel.layout(track: nil, event: Self.event(link: nil), metrics: metrics)
        #expect(with.textWidth < without.textWidth || with.panelWidth > without.panelWidth)
    }

    @Test("Без ссылки кнопки нет")
    func кнопкиНет() {
        #expect(PreviewPanel.joinLink(track: nil, event: Self.event(link: nil)) == nil)
        #expect(PreviewPanel.joinLink(track: nil, event: nil) == nil)
    }
}
