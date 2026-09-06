import TrunookXPC
import AudioToolbox
import AVFoundation
import CoreAudio
import Foundation

/// Отвод звука системы: всё, что слышно из динамиков, приходит буферами.
///
/// **Почему отвод CoreAudio, а не `ScreenCaptureKit`.** Оба умеют отдать
/// звук системы, но просят разного. `SCStream` требует доступ «Запись
/// экрана» — тот самый, которого у приложения нет и который отдаёт заодно
/// всё содержимое чужих окон. Отводу нужен только звук
/// (`kTCCServiceAudioCapture`, «Запись экрана и звука системы» → звук).
/// За меньшее разрешение и берём.
///
/// **Себя исключаем из отвода.** Иначе в запись встречи попадёт мурчание
/// выреза и сигнал таймера, а если приложение проговаривает ответ вслух —
/// то и он, кругом через собственную запись.
///
/// **Звук при этом слышно.** `muteBehavior = .unmuted`: отвод слушает
/// поток, а не перехватывает его. Встреча продолжается как шла.
///
/// Отводы появились в macOS 14.2 — отсюда и порог. Сама запись с
/// расшифровкой просит больше (macOS 26), но это ограничение другой службы,
/// и смешивать их в одном признаке незачем.
@available(macOS 14.2, *)
final class SystemAudioTap {
    /// Формат, в котором приходят кадры. Задаёт его сама система по
    /// нынешнему устройству вывода — свой навязать нельзя.
    let format: AudioStreamBasicDescription

    /// Готовый буфер звука. Зовётся на потоке звуковой подсистемы —
    /// на нём нельзя ни ждать, ни трогать вёрстку.
    var onBuffer: ((AVAudioPCMBuffer) -> Void)?

    /// Сколько кадров пришло. Отдельно от буфера ради пробы: ей нужен
    /// один вопрос — «идёт ли звук вообще», и собирать ради него буфер
    /// незачем.
    var onFrames: ((Int) -> Void)?

    /// Своя очередь для всего, что трогает звуковую подсистему.
    ///
    /// Не украшательство и не осторожность впрок: поймано пробой. При первом
    /// запуске `AudioDeviceStart` показывает системный запрос доступа
    /// и **не возвращается, пока человек не ответит**. На главном потоке это
    /// значит замерший вырез на всё время, что висит диалог, — ровно та же
    /// ошибка, что была с обходом дерева встречи.
    private static let queue = DispatchQueue(label: "com.trunook.audio.tap")

    private let tap: AudioObjectID
    private let device: AudioDeviceID
    private var procID: AudioDeviceIOProcID?
    private var isRunning = false

    /// Тот же формат, но в виде, пригодном для `AVAudioFile`: в нём и
    /// заводится файл дорожки.
    let pcmFormat: AVAudioFormat

    private init?(tap: AudioObjectID, device: AudioDeviceID, format: AudioStreamBasicDescription) {
        var description = format
        guard let pcmFormat = AVAudioFormat(streamDescription: &description) else {
            return nil
        }
        self.tap = tap
        self.device = device
        self.format = format
        self.pcmFormat = pcmFormat
    }

    // MARK: - Поднять и разобрать

    /// Поднимает отвод и приватное агрегатное устройство вокруг него.
    ///
    /// Агрегатное устройство нужно обязательно: сам отвод — источник без
    /// часов, читать из него напрямую нечем. Часы даёт подчинённое
    /// устройство — нынешний вывод, тот самый, чей звук мы и слушаем.
    ///
    /// Устройство приватное: иначе оно появится в системной панели звука
    /// у всех на виду и переживёт падение приложения.
    ///
    /// Ответ приходит на главный поток — с ним дальше работает вёрстка.
    static func open(_ done: @escaping (SystemAudioTap?) -> Void) {
        queue.async {
            let session = build()
            DispatchQueue.main.async { done(session) }
        }
    }

    private static func build() -> SystemAudioTap? {
        let description = CATapDescription(
            __stereoGlobalTapButExcludeProcesses: [NSNumber(value: ownProcessObject())]
        )
        description.name = "Trunook"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        guard AudioHardwareCreateProcessTap(description, &tap) == noErr,
              tap != AudioObjectID(kAudioObjectUnknown)
        else {
            DebugLog.write("отвод: не создался")
            return nil
        }

        guard let uid = AudioDevices.string(tap, kAudioTapPropertyUID),
              let format = format(of: tap),
              let clock = AudioDevices.defaultOutput?.uid
        else {
            DebugLog.write("отвод: нет номера, формата или устройства вывода")
            AudioHardwareDestroyProcessTap(tap)
            return nil
        }

        let settings: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Trunook",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: clock]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: uid]],
        ]
        var device = AudioDeviceID(kAudioObjectUnknown)
        guard AudioHardwareCreateAggregateDevice(settings as CFDictionary, &device) == noErr,
              device != AudioDeviceID(kAudioObjectUnknown)
        else {
            DebugLog.write("отвод: агрегатное устройство не создалось")
            AudioHardwareDestroyProcessTap(tap)
            return nil
        }

        guard let session = SystemAudioTap(tap: tap, device: device, format: format) else {
            DebugLog.write("отвод: формат не переводится в AVAudioFormat")
            AudioHardwareDestroyAggregateDevice(device)
            AudioHardwareDestroyProcessTap(tap)
            return nil
        }
        return session
    }

    /// Пускает звук. Здесь и висит запрос доступа при первом заходе, поэтому
    /// ответ асинхронный и приходит на главный поток.
    func start(_ done: @escaping (Bool) -> Void) {
        Self.queue.async { [self] in
            let started = startNow()
            DispatchQueue.main.async { done(started) }
        }
    }

    private func startNow() -> Bool {
        guard !isRunning else { return true }
        var procID: AudioDeviceIOProcID?
        let created = AudioDeviceCreateIOProcIDWithBlock(&procID, device, nil) {
            [weak self] _, input, _, _, _ in
            self?.receive(input)
        }
        guard created == noErr, let procID else {
            DebugLog.write("отвод: обработчик не создался")
            return false
        }
        self.procID = procID
        guard AudioDeviceStart(device, procID) == noErr else {
            DebugLog.write("отвод: устройство не запустилось")
            AudioDeviceDestroyIOProcID(device, procID)
            self.procID = nil
            return false
        }
        isRunning = true
        return true
    }

    /// Разбирает всё, что подняли.
    ///
    /// Забыть нельзя: агрегатное устройство переживает объект и остаётся
    /// в системе до перезапуска звуковой подсистемы.
    ///
    /// Обработчик кадров снимается первым делом: остановленное, но живое
    /// устройство иначе успевает позвать его ещё раз уже после того,
    /// как принимающая сторона всё убрала. Тот же порядок, что
    /// у `SpeechListener.cleanUp` с отводом микрофона.
    func close() {
        onBuffer = nil
        onFrames = nil
        Self.queue.async { [self] in
            if let procID {
                if isRunning { AudioDeviceStop(device, procID) }
                AudioDeviceDestroyIOProcID(device, procID)
                self.procID = nil
                isRunning = false
            }
            AudioHardwareDestroyAggregateDevice(device)
            AudioHardwareDestroyProcessTap(tap)
        }
    }

    // MARK: - Приём кадров

    private func receive(_ input: UnsafePointer<AudioBufferList>) {
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = list.first, first.mDataByteSize > 0 else { return }

        let bytesPerFrame = max(pcmFormat.streamDescription.pointee.mBytesPerFrame, 1)
        onFrames?(Int(first.mDataByteSize / bytesPerFrame))

        guard let onBuffer,
              let buffer = AVAudioPCMBuffer(pcmFormat: pcmFormat, bufferListNoCopy: input)
        else { return }
        onBuffer(buffer)
    }

    // MARK: - Мелочи CoreAudio

    /// Номер своего процесса в звуковой подсистеме — не `pid`, а собственный
    /// объект CoreAudio: только его и понимает описание отвода.
    private static func ownProcessObject() -> AudioObjectID {
        var address = AudioDevices.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = getpid()
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address,
            UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object
        )
        return object
    }

    private static func format(of tap: AudioObjectID) -> AudioStreamBasicDescription? {
        var address = AudioDevices.address(kAudioTapPropertyFormat)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format) == noErr,
              format.mSampleRate > 0
        else { return nil }
        return format
    }
}
