import TrunookXPC
import Foundation
import IOKit.pwr_mgt

/// Не даёт экрану гаснуть, а значит и блокироваться.
///
/// Через `IOPMAssertionCreateWithName` — тот же механизм, которым пользуется
/// системный `caffeinate`. Публичный, разрешений не требует и не трогает
/// настройки энергосбережения: пока живёт ассерция, система просто не считает
/// простой поводом погасить экран, а как только её отпустили — всё возвращается
/// к обычным правилам само.
///
/// Экран и блокировка тут одно и то же: блокировка наступает вслед за гашением
/// экрана, и удержав экран, удерживаешь и её.
final class WakeGuard: ObservableObject {
    /// Держим ли экран прямо сейчас.
    @Published private(set) var isOn = false

    /// Срок вышел, и удержание снялось само. Отдельно от обычного выключения:
    /// человек этого не нажимал, и не сказать ему значит оставить его гадать,
    /// почему экран вдруг снова гаснет.
    var onExpired: (() -> Void)?

    private let settings: Settings

    /// Ассерция живёт ровно столько, сколько процесс: система отпускает её
    /// сама, если приложение упало или его сняли. Поэтому состояние
    /// не сохраняется между запусками — иначе после перезапуска экран
    /// молча не гас бы, и связать это было бы не с чем.
    private var assertion: IOPMAssertionID = IOPMAssertionID(0)

    /// Будильник на снятие удержания. Ноль минут в настройках — будильника
    /// нет вовсе.
    private var limitTimer: Timer?

    init(settings: Settings = .shared) {
        self.settings = settings
    }

    /// Заданный срок в минутах. Ноль — без ограничения.
    var limitMinutes: Int { settings.caffeineLimitMinutes }

    /// Имя, которое показывают `pmset -g assertions` и Мониторинг системы
    /// в столбце «Препятствует переходу в режим сна». По нему человек поймёт,
    /// кто именно держит его экран, — и это единственный способ выяснить
    /// такое снаружи.
    ///
    /// Латиницей, и это не небрежность: реестр ассерций молча отбрасывает
    /// имена не в ASCII. Проверено — русское название доходило туда пустой
    /// строкой, и приложение переставало быть узнаваемым ровно там, где
    /// его ищут. По той же причине имя не переводится: его читает система,
    /// а не человек в интерфейсе.
    private static let reason = "Trunook: keeping the display awake" as CFString

    deinit {
        limitTimer?.invalidate()
        release()
    }

    @discardableResult
    func toggle() -> Bool {
        isOn ? disable() : enable()
        return isOn
    }

    func enable() {
        guard !isOn else { return }
        var identifier = IOPMAssertionID(0)
        let status = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            Self.reason,
            &identifier
        )
        guard status == kIOReturnSuccess else {
            // Промолчать нельзя: подложка под чашкой сказала бы, что экран
            // держится, а он бы гас.
            DebugLog.write("бодрость: не удалось удержать экран, код \(status)")
            return
        }
        assertion = identifier
        isOn = true
        scheduleLimit()
        DebugLog.write("бодрость: экран удерживается"
                       + (limitMinutes > 0 ? ", срок \(limitMinutes) мин" : ", без ограничения"))
    }

    /// Заводит будильник на снятие удержания.
    ///
    /// Срок читается в момент включения, а не хранится: человек может поменять
    /// его в настройках, пока чашка горит, и брать старое значение было бы
    /// враньём. Заново заведённая чашка возьмёт новый срок.
    private func scheduleLimit() {
        limitTimer?.invalidate()
        limitTimer = nil
        let minutes = limitMinutes
        guard minutes > 0 else { return }

        let timer = Timer(timeInterval: TimeInterval(minutes) * 60, repeats: false) { [weak self] _ in
            self?.expire()
        }
        // .common, иначе будильник замирает, пока человек держит открытым меню
        // или тянет ползунок, — и срок растягивался бы на это время.
        RunLoop.main.add(timer, forMode: .common)
        limitTimer = timer
    }

    /// Отладочный вход: ждать полчаса, чтобы посмотреть, что будет по срокам,
    /// нельзя, а посмотреть надо.
    func debugExpireNow() { expire() }

    private func expire() {
        guard isOn else { return }
        release()
        isOn = false
        limitTimer = nil
        DebugLog.write("бодрость: срок вышел, экран отпущен")
        onExpired?()
    }

    func disable() {
        guard isOn else { return }
        limitTimer?.invalidate()
        limitTimer = nil
        release()
        isOn = false
        DebugLog.write("бодрость: экран отпущен")
    }

    /// Отпустить ассерцию, не трогая наблюдаемое состояние: нужно и обычному
    /// выключению, и завершению приложения.
    private func release() {
        guard assertion != IOPMAssertionID(0) else { return }
        IOPMAssertionRelease(assertion)
        assertion = IOPMAssertionID(0)
    }
}
