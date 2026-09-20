import Foundation
import Testing
@testable import Trunook

@Suite("Встреча в своём приложении: Zoom и Телемост")
struct MeetingAppsTests {
    // MARK: - Кто чем управляется

    @Test("Телемост — кнопками окна, Zoom — меню")
    func откудаУправление() {
        #expect(MeetingApp.telemost.controls == .windowButtons)
        #expect(MeetingApp.zoom.controls == .menu)
        #expect(MeetingApp.named("us.zoom.xos") == .zoom)
        #expect(MeetingApp.named("com.google.Chrome") == nil)
        #expect(MeetingApp.named(nil) == nil)
    }

    @Test("Окно звонка Zoom отличается от главного окна")
    func окноЗвонка() {
        #expect(MeetingApp.zoom.isMeetingWindow(title: "Конференция Zoom"))
        #expect(MeetingApp.zoom.isMeetingWindow(title: "Zoom Meeting"))
        // Главное окно приложения стоит открытым всегда — принять его
        // за звонок значило бы показывать кнопки встречи круглые сутки.
        #expect(!MeetingApp.zoom.isMeetingWindow(title: "Zoom Workplace"))
        #expect(!MeetingApp.zoom.isMeetingWindow(title: "Вход в систему"))
    }

    // MARK: - Подписи меню Zoom

    /// Подписи сняты с живого звонка 19 сентября.
    @Test("Микрофон, камера и демонстрация находятся по точной подписи")
    func подписиМеню() {
        #expect(MeetingApp.zoom.menuTitles(for: .microphone).contains("выключить звук"))
        #expect(MeetingApp.zoom.menuTitles(for: .camera).contains("начать видео"))
        #expect(MeetingApp.zoom.menuTitles(for: .share).contains("начать совместное использование"))
    }

    /// Главное в этой таблице — чего в ней нет.
    ///
    /// В меню Zoom рядом с «Выключить звук» стоит «Выключить звук для всех»,
    /// а рядом с выходом из конференции — «Выйти из Zoom Workplace», то есть
    /// выход из всего приложения. Совпадение по подстроке однажды нажало бы
    /// не то, и узнал бы об этом человек уже после.
    @Test("Опасные соседние пункты меню в таблицу не попадают")
    func опасныеСоседи() {
        let dangerous = ["выключить звук для всех", "попросить всех включить звук",
                         "выйти из zoom workplace", "завершить zoom.us принудительно"]
        for action in MeetingAction.allCases {
            let titles = MeetingApp.zoom.menuTitles(for: action)
            for item in dangerous {
                #expect(!titles.contains(item))
            }
        }
    }

    /// У Zoom в меню нет ни руки, ни выхода, а кнопок панели звонка окно
    /// наружу не отдаёт. Кнопка, которой нечем управлять, не показывается.
    @Test("Руки и выхода у Zoom нет — и это записано, а не забыто")
    func чегоНетУZoom() {
        #expect(MeetingApp.zoom.menuTitles(for: .hand).isEmpty)
        #expect(MeetingApp.zoom.menuTitles(for: .leave).isEmpty)
    }

    /// Почему сверка идёт по полному совпадению, а не по опорному слову.
    ///
    /// «Выключить звук для всех» содержит «Выключить звук» целиком: по
    /// подстроке нашлось бы оно — и нажатие выключило бы микрофоны всем
    /// участникам встречи. Ровно этого и не должно случиться.
    @Test("Опасный пункт содержит безопасный как подстроку — потому и сверка точная")
    func почемуТочнаяСверка() {
        let safe = "выключить звук"
        let dangerous = "выключить звук для всех"
        #expect(dangerous.contains(safe))
        #expect(MeetingApp.zoom.menuTitles(for: .microphone).contains(safe))
        #expect(!MeetingApp.zoom.menuTitles(for: .microphone).contains(dangerous))
    }

    @Test("У Телемоста меню не спрашивают вовсе")
    func телемостБезМеню() {
        for action in MeetingAction.allCases {
            #expect(MeetingApp.telemost.menuTitles(for: action).isEmpty)
        }
    }

    // MARK: - Состояние по подписи

    /// Подписи взяты из живых звонков: Телемост — кнопки окна, Zoom — меню.
    /// Подпись описывает будущее действие, поэтому «Включить» значит,
    /// что сейчас выключено.
    @Test("Состояние читается по подписи одинаково у обоих приложений")
    func состояниеПоПодписи() {
        #expect(!MeetingService.isOn(labels: ["Включить микрофон"]))
        #expect(MeetingService.isOn(labels: ["Выключить микрофон"]))
        #expect(!MeetingService.isOn(labels: ["Включить звук"]))
        #expect(MeetingService.isOn(labels: ["Выключить звук"]))
        #expect(!MeetingService.isOn(labels: ["Начать видео"]))
        #expect(MeetingService.isOn(labels: ["Остановить видео"]))
        #expect(!MeetingService.isOn(labels: ["Демонстрация", "Начать демонстрацию экрана"]))
        #expect(!MeetingService.isOn(labels: ["Поднять руку"]))
        #expect(MeetingService.isOn(labels: ["Опустить руку"]))
    }

    /// Кнопки Телемоста находятся той же таблицей опорных слов, какой
    /// находились кнопки страницы: подписи совпали до слова.
    @Test("Кнопки Телемоста ложатся на прежнюю таблицу подписей")
    func подписиТелемоста() {
        func matches(_ action: MeetingAction, _ label: String) -> Bool {
            action.labels.contains { label.lowercased().contains($0) }
        }
        #expect(matches(.microphone, "Включить микрофон"))
        #expect(matches(.camera, "Включить камеру"))
        #expect(matches(.share, "Демонстрация Начать демонстрацию экрана"))
        #expect(matches(.hand, "Поднять руку"))
        #expect(matches(.leave, "Выйти из встречи"))
        // Соседние кнопки панели звонка не должны выдавать себя за них.
        #expect(!matches(.leave, "Участники Посмотреть список участников"))
        #expect(!matches(.hand, "Конспектировать с Алисой Про"))
    }
}
