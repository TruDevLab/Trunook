import Foundation
import TrunookXPC

/// Нагрузка на систему: процессор, память, диск.
///
/// Опрашивается только пока панель открыта. Мониторинг, работающий вхолостую,
/// сам становится нагрузкой — а показывать он её будет себе же.
///
/// Видеокарты здесь нет намеренно. Публичного способа узнать её загрузку
/// в macOS не существует, а `PerformanceStatistics` из `IOAccelerator`,
/// на которые обычно ссылаются, на этой технике отдают ноль даже под
/// настоящей нагрузкой: проверено отдельной пробой с непрерывным размытием
/// большого изображения — все замеры вернули нули. Показывать заведомо
/// пустую шкалу хуже, чем не показывать вовсе.
final class MonitorService: ObservableObject {
    /// Снимок нагрузки. Значения долей — от нуля до единицы.
    struct Sample: Equatable {
        /// `nil`, пока не набран первый промежуток: доля процессора считается
        /// разностью счётчиков, и по одному замеру её не существует.
        var cpu: Double?
        var memoryUsed: Double = 0
        var memoryTotal: Double = 0
        var diskUsed: Double = 0
        var diskTotal: Double = 0

        var memoryShare: Double { memoryTotal > 0 ? memoryUsed / memoryTotal : 0 }
        var diskShare: Double { diskTotal > 0 ? diskUsed / diskTotal : 0 }
    }

    @Published private(set) var sample = Sample()

    /// Как часто пересчитываем. Полсекунды: процессор успевает показать
    /// отклик на действие, а стоит замер сотых долей процента.
    private static let interval: TimeInterval = 0.5

    private var timer: Timer?
    /// Счётчики процессора с прошлого замера. Обнуляются при остановке:
    /// иначе первое же значение после долгого перерыва оказалось бы средним
    /// за всё время, пока панель была закрыта, — и выглядело бы как правда.
    private var previousTicks: CPUTicks?

    // MARK: - Жизненный цикл

    func start() {
        guard timer == nil else { return }
        previousTicks = Self.cpuTicks()
        refreshMemoryAndDisk()

        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        DebugLog.write("мониторинг: опрос начат")
    }

    func stop() {
        guard timer != nil else { return }
        timer?.invalidate()
        timer = nil
        previousTicks = nil
        sample.cpu = nil
        DebugLog.write("мониторинг: опрос остановлен")
    }

    private func tick() {
        refreshCPU()
        refreshMemoryAndDisk()
    }

    // MARK: - Процессор

    /// Сумма тиков по всем ядрам. Разность двух таких сумм и есть загрузка
    /// за промежуток.
    private struct CPUTicks {
        var busy: Double
        var total: Double
    }

    private func refreshCPU() {
        guard let now = Self.cpuTicks() else { return }
        defer { previousTicks = now }
        guard let before = previousTicks else { return }

        let busy = now.busy - before.busy
        let total = now.total - before.total
        guard total > 0 else { return }
        sample.cpu = min(1, max(0, busy / total))
    }

    private static func cpuTicks() -> CPUTicks? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(
            mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount
        ) == KERN_SUCCESS, let info else { return nil }

        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            )
        }

        let ticks = info.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) { $0 }
        var busy = 0.0
        var total = 0.0
        for core in 0..<Int(count) {
            let base = core * Int(CPU_STATE_MAX)
            let user = Double(ticks[base + Int(CPU_STATE_USER)])
            let system = Double(ticks[base + Int(CPU_STATE_SYSTEM)])
            let nice = Double(ticks[base + Int(CPU_STATE_NICE)])
            let idle = Double(ticks[base + Int(CPU_STATE_IDLE)])
            busy += user + system + nice
            total += user + system + nice + idle
        }
        return CPUTicks(busy: busy, total: total)
    }

    // MARK: - Память и диск

    private func refreshMemoryAndDisk() {
        sample.memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
        sample.memoryUsed = Self.memoryUsed()

        if let disk = Self.disk() {
            sample.diskTotal = disk.total
            sample.diskUsed = disk.used
        }
    }

    /// Занятая память по тому же счёту, что и в Мониторинге системы:
    /// память приложений плюс зарезервированная ядром плюс сжатая.
    ///
    /// Формула выбрана не за красоту: по нажатию на плитку открывается
    /// именно Мониторинг системы, и числа обязаны сойтись. Более простое
    /// «активная плюс зарезервированная плюс сжатая» давало на семь
    /// процентных пунктов меньше.
    private static func memoryUsed() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let page = Double(vm_kernel_page_size)
        let application = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        let wired = Double(stats.wire_count)
        let compressed = Double(stats.compressor_page_count)
        return max(0, (application + wired + compressed) * page)
    }

    /// Место на диске с данными, а не на системном томе: системный том
    /// доступен только для чтения и всегда занят целиком — показывать
    /// его сто процентов было бы бессмысленно.
    private static func disk() -> (used: Double, total: Double)? {
        let url = URL(fileURLWithPath: "/System/Volumes/Data")
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacityForImportantUsage
        else { return nil }
        return (used: max(0, Double(total) - Double(free)), total: Double(total))
    }

    // MARK: - Запись величин

    /// Гигабайты с одним знаком. Десятичные, а не двоичные: так же считает
    /// сама macOS, и расхождение с Finder сбивало бы с толку.
    ///
    /// Разделитель дробной части берётся из системы: без него «14.5» стояло бы
    /// и в русском интерфейсе, где принята запятая.
    static func gigabytes(_ bytes: Double, locale: Locale = .current) -> String {
        String(format: "%.1f", locale: locale, bytes / 1e9)
    }

    static func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }
}
