import Foundation

/// Приложение встречи, живущее своим окном, а не вкладкой браузера.
///
/// Разные они не названием, а тем, где у них органы управления звонком.
/// Снято с живых звонков 19 сентября:
///
/// - **Телемост** (Qt) честно отдаёт кнопки панели звонка: «Включить
///   микрофон», «Включить камеру», «Демонстрация», «Поднять руку», «Выйти
///   из встречи» — с ними и работаем.
/// - **Zoom** окно звонка наружу почти не отдаёт: в дереве его окна
///   «Конференция Zoom» всего две кнопки, и обе к звонку не относятся.
///   Зато те же действия лежат в строке меню, и по их подписи видно
///   состояние: «Включить звук» против «Выключить звук».
enum MeetingApp: String, CaseIterable, Identifiable {
    case telemost = "ru.yandex.desktop.telemost"
    case zoom = "us.zoom.xos"

    var id: String { rawValue }
    var bundleID: String { rawValue }

    /// Где искать органы управления.
    enum Controls {
        /// Кнопки в самом окне.
        case windowButtons
        /// Пункты строки меню.
        case menu
    }

    var controls: Controls {
        switch self {
        case .telemost: return .windowButtons
        case .zoom: return .menu
        }
    }

    /// По какому окну видно, что звонок идёт.
    ///
    /// Только для тех, кем управляют через меню: у меню нет своего признака
    /// «звонок идёт» — половина пунктов конференции стоит там и вне звонка,
    /// просто недоступной. Окно же заводится ровно на звонок.
    ///
    /// Сравнение по вхождению в нижнем регистре: заголовок бывает
    /// и «Конференция Zoom», и «Zoom Meeting» — смотря на каком языке
    /// у человека само приложение.
    var meetingWindowTitles: [String] {
        switch self {
        case .zoom: return ["конференция zoom", "zoom meeting", "zoom-конференция"]
        case .telemost: return []
        }
    }

    /// Точные подписи пунктов меню для действия.
    ///
    /// Именно точные, а не опорные слова, как у кнопок страницы, — и это
    /// не придирка. В меню Zoom рядом с «Выключить звук» стоит «Выключить
    /// звук для всех», а рядом с выходом из конференции — «Выйти из Zoom
    /// Workplace», то есть выход из всего приложения. Совпадение
    /// по подстроке однажды нажало бы не то, и узнал бы об этом человек
    /// уже после.
    ///
    /// Обе подписи — и включающая, и выключающая: по той, что стоит сейчас,
    /// читается состояние (см. `MeetingAction.offWords`).
    func menuTitles(for action: MeetingAction) -> [String] {
        switch self {
        case .telemost:
            return []
        case .zoom:
            switch action {
            case .microphone:
                return ["включить звук", "выключить звук", "unmute audio", "mute audio"]
            case .camera:
                return ["начать видео", "остановить видео", "start video", "stop video"]
            case .share:
                return [
                    "начать совместное использование", "остановить совместное использование",
                    "начать демонстрацию экрана", "остановить демонстрацию экрана",
                    "start share", "stop share", "start screen share", "stop screen share",
                ]
            // Ни руки, ни выхода в меню Zoom нет вовсе: и то и другое живёт
            // на панели звонка, а её кнопок окно наружу не отдаёт. Показывать
            // кнопку, которой нечем управлять, хуже, чем не показывать.
            case .hand, .leave, .copyLink, .output, .input, .record:
                return []
            }
        }
    }

    static func named(_ bundleID: String?) -> MeetingApp? {
        guard let bundleID else { return nil }
        return MeetingApp(rawValue: bundleID)
    }

    /// Похож ли заголовок окна на окно идущего звонка.
    func isMeetingWindow(title: String) -> Bool {
        let lowered = title.lowercased()
        return meetingWindowTitles.contains { lowered.contains($0) }
    }
}
