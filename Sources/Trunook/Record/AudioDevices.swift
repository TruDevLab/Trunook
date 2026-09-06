import TrunookXPC
import CoreAudio
import Foundation

/// Звуковое устройство системы.
///
/// Значение, а не ссылка на CoreAudio: по списку считается перебор кнопкой,
/// а перебор проверяется тестом — с живыми `AudioDeviceID` его было бы
/// не поднять.
struct AudioDevice: Equatable, Identifiable {
    let id: AudioDeviceID
    /// Постоянный номер устройства. `AudioDeviceID` живёт до перезагрузки
    /// звуковой подсистемы, `uid` — всегда, и хранить в настройках можно
    /// только его.
    let uid: String
    let name: String
}

/// Список звуковых устройств и смена нынешнего.
///
/// Тонкая обёртка над CoreAudio: в проекте до этого не было ни одного
/// обращения к нему. Всё, что можно вынести в чистую функцию, вынесено —
/// живой звуковой подсистемы в тестах нет.
enum AudioDevices {
    // MARK: - Перебор по кругу

    /// Следующее устройство за нынешним.
    ///
    /// Чистая функция под тестом: это вся логика кнопки в панели встречи,
    /// и ошибиться в ней легко на двух случаях — когда устройство одно
    /// и когда нынешнего в списке уже нет (наушники выдернули).
    ///
    /// Нынешнее пропало — берём первое, а не молчим: кнопку нажали, значит
    /// хотят сменить, и остаться ни с чем хуже всего.
    static func next(after current: AudioDevice?, in devices: [AudioDevice]) -> AudioDevice? {
        guard !devices.isEmpty else { return nil }
        guard let current, let index = devices.firstIndex(where: { $0.uid == current.uid })
        else { return devices[0] }
        return devices[(index + 1) % devices.count]
    }

    // MARK: - Списки

    /// Устройства, куда звук идёт.
    static func outputs() -> [AudioDevice] {
        all().filter { channels(of: $0.id, scope: kAudioObjectPropertyScopeOutput) > 0 }
    }

    /// Устройства, откуда звук слушают.
    static func inputs() -> [AudioDevice] {
        all().filter { channels(of: $0.id, scope: kAudioObjectPropertyScopeInput) > 0 }
    }

    /// Все устройства, отсортированные по имени.
    ///
    /// Порядок системы — порядок появления, и он меняется от перезагрузки
    /// к перезагрузке. Перебор кнопкой по такому списку прыгал бы: сегодня
    /// за встроенными наушники, завтра — наоборот.
    private static func all() -> [AudioDevice] {
        var address = address(kAudioHardwarePropertyDevices)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size
        ) == noErr, size > 0 else { return [] }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids
        ) == noErr else { return [] }

        return ids.compactMap { device(id: $0) }.sorted { $0.name < $1.name }
    }

    private static func device(id: AudioDeviceID) -> AudioDevice? {
        guard let uid = string(id, kAudioDevicePropertyDeviceUID),
              let name = string(id, kAudioObjectPropertyName)
        else { return nil }
        return AudioDevice(id: id, uid: uid, name: name)
    }

    // MARK: - Нынешнее устройство

    static var defaultOutput: AudioDevice? {
        current(kAudioHardwarePropertyDefaultOutputDevice)
    }

    static var defaultInput: AudioDevice? {
        current(kAudioHardwarePropertyDefaultInputDevice)
    }

    /// Ставит устройство вывода.
    ///
    /// Два свойства, а не одно: `DefaultOutputDevice` отвечает за музыку
    /// и голоса, `DefaultSystemOutputDevice` — за системные звуки. Меняют
    /// их в панели звука вместе, и разошедшаяся пара выглядит поломкой:
    /// разговор в наушниках, а щелчки из динамиков.
    @discardableResult
    static func setDefaultOutput(_ device: AudioDevice) -> Bool {
        let main = set(kAudioHardwarePropertyDefaultOutputDevice, to: device.id)
        set(kAudioHardwarePropertyDefaultSystemOutputDevice, to: device.id)
        if main { DebugLog.write("звук: вывод — \(device.name)") }
        return main
    }

    @discardableResult
    static func setDefaultInput(_ device: AudioDevice) -> Bool {
        let done = set(kAudioHardwarePropertyDefaultInputDevice, to: device.id)
        if done { DebugLog.write("звук: ввод — \(device.name)") }
        return done
    }

    private static func current(_ selector: AudioObjectPropertySelector) -> AudioDevice? {
        var address = address(selector)
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id
        ) == noErr else { return nil }
        return device(id: id)
    }

    @discardableResult
    private static func set(_ selector: AudioObjectPropertySelector, to id: AudioDeviceID) -> Bool {
        var address = address(selector)
        var value = id
        return AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
            UInt32(MemoryLayout<AudioDeviceID>.size), &value
        ) == noErr
    }

    // MARK: - Мелочи CoreAudio

    /// Адрес свойства. У всех обращений здесь область глобальная, кроме
    /// пересчёта каналов — тому нужна сторона.
    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    /// Сколько у устройства каналов с этой стороны.
    ///
    /// Так и отличается микрофон от динамиков: отдельного признака
    /// у устройства нет. Наушники с микрофоном имеют каналы с обеих сторон
    /// и законно попадают в оба списка.
    private static func channels(of id: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        var address = address(kAudioDevicePropertyStreamConfiguration, scope: scope)
        var size = UInt32(0)
        guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0
        else { return 0 }

        // `AudioBufferList` — структура переменной длины: за первым буфером
        // следуют остальные, и обычным `var list = AudioBufferList()` тут
        // не обойтись — прочитался бы только первый.
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, raw) == noErr else { return 0 }

        let list = UnsafeMutableAudioBufferListPointer(
            raw.assumingMemoryBound(to: AudioBufferList.self)
        )
        return list.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    /// Строковое свойство — имя устройства или его номер.
    ///
    /// Через `Unmanaged`, а не в переменную `CFString` напрямую: эти свойства
    /// отдают строку с уже поднятым счётчиком ссылок, и владение переходит
    /// к вызывающему. Запись мимо `Unmanaged` компилятор и ругает —
    /// «forming UnsafeMutableRawPointer to a variable of type CFString», —
    /// и ругает по делу: там утекала бы строка на каждый опрос устройств.
    static func string(
        _ id: AudioObjectID,
        _ selector: AudioObjectPropertySelector
    ) -> String? {
        var address = address(selector)
        let pointer = UnsafeMutablePointer<Unmanaged<CFString>?>.allocate(capacity: 1)
        defer { pointer.deallocate() }
        pointer.pointee = nil

        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer) == noErr,
              let value = pointer.pointee
        else { return nil }

        let text = value.takeRetainedValue() as String
        return text.isEmpty ? nil : text
    }
}
