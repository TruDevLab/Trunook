import TrunookXPC
import Foundation
import IOKit.ps

/// Следит за питанием и сообщает о переходах: подключили зарядку,
/// отключили, заряд упал ниже порога.
final class BatteryMonitor: ObservableObject {
    @Published private(set) var percentage: Int = 100
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false
    @Published private(set) var isPresent = false

    /// Вызывается при переходах, а не при каждом обновлении.
    var onEvent: ((Activity.Kind) -> Void)?

    private let settings: Settings
    private var runLoopSource: CFRunLoopSource?
    private var didWarnAboutLowBattery = false
    private var lastPluggedIn: Bool?

    init(settings: Settings = .shared) {
        self.settings = settings
    }

    func start() {
        refresh()
        // Система сама будит нас при изменении состояния питания —
        // опрашивать по таймеру не нужно.
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<BatteryMonitor>.fromOpaque(context)
                .takeUnretainedValue()
                .refresh()
        }, context)?.takeRetainedValue() else {
            DebugLog.write("батарея: не удалось подписаться на уведомления IOKit")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
    }

    func refresh() {
        guard let snapshot = readPowerSource() else { return }

        let wasPluggedIn = lastPluggedIn
        if lastPluggedIn == nil || wasPluggedIn != snapshot.isPluggedIn {
            DebugLog.write(
                "батарея: \(snapshot.percentage)%, "
                + "питание \(snapshot.isPluggedIn ? "подключено" : "от батареи"), "
                + "заряжается \(snapshot.isCharging)"
            )
        }
        percentage = snapshot.percentage
        isCharging = snapshot.isCharging
        isPluggedIn = snapshot.isPluggedIn
        isPresent = true
        lastPluggedIn = snapshot.isPluggedIn

        guard settings.batteryEnabled else { return }

        // Первое чтение при запуске — это не событие, а исходное состояние.
        if let wasPluggedIn, wasPluggedIn != snapshot.isPluggedIn {
            onEvent?(
                snapshot.isPluggedIn
                    ? .powerConnected(percentage: snapshot.percentage)
                    : .powerDisconnected(percentage: snapshot.percentage)
            )
        }

        updateLowBatteryWarning(snapshot)
    }

    private func updateLowBatteryWarning(_ snapshot: Snapshot) {
        let threshold = settings.lowBatteryThreshold

        // Сбрасываем флаг с запасом в 5 процентов, иначе на границе порога
        // предупреждение будет мигать при каждом колебании заряда.
        if snapshot.isPluggedIn || snapshot.percentage > threshold + 5 {
            didWarnAboutLowBattery = false
            return
        }

        guard settings.warnOnLowBattery,
              !didWarnAboutLowBattery,
              !snapshot.isPluggedIn,
              snapshot.percentage <= threshold
        else { return }

        didWarnAboutLowBattery = true
        onEvent?(.lowBattery(percentage: snapshot.percentage))
    }

    // MARK: - Чтение IOKit

    private struct Snapshot {
        let percentage: Int
        let isCharging: Bool
        let isPluggedIn: Bool
    }

    private func readPowerSource() -> Snapshot? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0
            else { continue }

            let state = description[kIOPSPowerSourceStateKey] as? String
            return Snapshot(
                percentage: Int((Double(current) / Double(maximum) * 100).rounded()),
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isPluggedIn: state == kIOPSACPowerValue
            )
        }
        return nil
    }
}
