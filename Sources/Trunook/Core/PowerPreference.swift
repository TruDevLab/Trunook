import TrunookXPC
import AppKit
import Combine
import IOKit.ps

/// Когда приложение переходит в режим энергосбережения.
enum PowerSavingMode: String, CaseIterable, Identifiable {
    case never
    /// Только когда в macOS включён «Режим энергосбережения».
    case lowPowerMode
    /// Ещё и всё время работы от аккумулятора.
    case battery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .never: return t("Никогда")
        case .lowPowerMode: return t("В режиме энергосбережения macOS")
        case .battery: return t("От аккумулятора и в режиме энергосбережения")
        }
    }
}

/// Режим энергосбережения приложения: включён ли он прямо сейчас.
///
/// Одно место на всё приложение, как `MotionPreference`, и по той же
/// причине: потребителей много — сценки, бегущая строка, сводки, опросы, —
/// и проверка питания, разложенная по ним, неизбежно разъехалась бы.
/// Потребители читают `saving` и подписываются на него; питание сами
/// не проверяет никто. Что режим отключает — `ENERGY.md`, раздел 2.
final class PowerPreference: ObservableObject {
    static let shared = PowerPreference()

    /// Режим действует прямо сейчас.
    @Published private(set) var saving = false
    /// В macOS включён «Режим энергосбережения».
    @Published private(set) var lowPowerMode: Bool
    /// Mac работает от аккумулятора.
    @Published private(set) var onBattery: Bool

    /// Отладочное включение и выключение поверх питания.
    private var forced: Bool?

    private let settings: Settings
    private var runLoopSource: CFRunLoopSource?
    private var settingsObservation: AnyCancellable?

    init(settings: Settings = .shared) {
        self.settings = settings
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        onBattery = Self.readOnBattery()

        // Уведомление приходит с произвольного потока — на главный.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(powerStateChanged),
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )
        subscribeToPowerSource()
        // `objectWillChange` приходит до записи — через очередь главного
        // потока настройка к этому мигу уже новая.
        settingsObservation = settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.recompute() }
        recompute()
    }

    /// Почему режим включён — для строки состояния в настройках.
    var reason: String? {
        guard saving else { return nil }
        if forced == true { return t("для проверки") }
        if lowPowerMode { return t("энергосбережение macOS") }
        return t("от аккумулятора")
    }

    /// Правило целиком — чистой функцией, чтобы проверить тестом.
    static func isSaving(mode: PowerSavingMode, lowPowerMode: Bool, onBattery: Bool) -> Bool {
        switch mode {
        case .never: return false
        case .lowPowerMode: return lowPowerMode
        case .battery: return lowPowerMode || onBattery
        }
    }

    /// Отладка: включить или выключить режим поверх питания; `nil` — вернуть
    /// решение питанию.
    func debugForce(_ value: Bool?) {
        forced = value
        recompute()
    }

    // MARK: - Источники

    @objc private func powerStateChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            recompute()
        }
    }

    private func subscribeToPowerSource() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let preference = Unmanaged<PowerPreference>.fromOpaque(context).takeUnretainedValue()
            let battery = PowerPreference.readOnBattery()
            if preference.onBattery != battery { preference.onBattery = battery }
            preference.recompute()
        }, context)?.takeRetainedValue() else {
            DebugLog.write("энергосбережение: не удалось подписаться на источник питания")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
    }

    private static func readOnBattery() -> Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue()
        else { return false }
        return (type as String) == kIOPSBatteryPowerValue
    }

    private func recompute() {
        let now = forced ?? Self.isSaving(
            mode: settings.powerSavingMode, lowPowerMode: lowPowerMode, onBattery: onBattery
        )
        guard now != saving else { return }
        saving = now
        DebugLog.write("энергосбережение: \(now ? "включено — \(reason ?? "")" : "выключено")")
    }
}
