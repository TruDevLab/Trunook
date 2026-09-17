import TrunookXPC
import AppKit

/// В какое приложение вставлять.
///
/// Вставка всегда шла туда, откуда пришли, и это верно ровно до первого
/// «а положи-ка в другое окно»: спросил модель, читая письмо, а ответ нужен
/// в заметке. Раньше для этого приходилось закрывать панель, переключаться
/// руками, возвращаться и вставлять из буфера.
///
/// Теперь цель видна прямо на кнопке и перебирается клавишей Tab — той же,
/// какой перебирается модель у команды: в панели это уже клавиша «поменять
/// то, на чём стоит подсветка».
enum PasteApps {
    /// Куда имеет смысл вставлять.
    ///
    /// Только приложения с окнами (`.regular`): агенты и службы без окон
    /// поля ввода не имеют вовсе, а список из тридцати невидимых имён
    /// перебирать нечем. Своё приложение исключено — вставлять ответ
    /// в самого себя незачем.
    static func candidates(excluding own: pid_t = ProcessInfo.processInfo.processIdentifier)
        -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { !$0.isTerminated && $0.processIdentifier != own }
            // По имени: порядок `runningApplications` случайный и меняется
            // между вызовами, а перебор клавишей обязан идти одинаково —
            // иначе второе нажатие Tab возвращает не туда, откуда пришли.
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    /// Следующее по кругу.
    ///
    /// По кругу, а не до упора: список чужой и длинный, и упереться в его
    /// конец значило бы заставить человека считать нажатия. Чистой функцией
    /// над номерами — `NSRunningApplication` в пробу не завести.
    static func next(after current: pid_t?, in list: [pid_t]) -> pid_t? {
        guard !list.isEmpty else { return nil }
        guard let current, let index = list.firstIndex(of: current) else { return list[0] }
        return list[(index + 1) % list.count]
    }

    static func next(after current: NSRunningApplication?, in list: [NSRunningApplication])
        -> NSRunningApplication? {
        let pids = list.map(\.processIdentifier)
        guard let pid = next(after: current?.processIdentifier, in: pids) else { return nil }
        return list.first { $0.processIdentifier == pid }
    }

    /// Имя для кнопки. Длинные имена режутся: строка действия и так несёт
    /// слово «Вставить».
    static func shortName(of app: NSRunningApplication?, limit: Int = 18) -> String? {
        guard let name = app?.localizedName, !name.isEmpty else { return nil }
        guard name.count > limit else { return name }
        return String(name.prefix(limit - 1)) + "…"
    }
}
