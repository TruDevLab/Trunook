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
        center.present(.clipboard(text: "текст", kind: .text))
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
        #expect(Activity(kind: .clipboard(text: "т", kind: .text)).isInteractive)
        #expect(!Activity(kind: .trackChanged).isInteractive)
    }

    @Test("Досрочное снятие очищает плашку")
    func снятие() {
        let center = ActivityCenter()
        center.present(.trackChanged)
        center.dismiss()
        #expect(center.current == nil)
    }
}
