import SwiftUI

// MARK: - Таймер

/// Остаток таймера или счёт секундомера и кнопка пуска.
struct TimerWidget: View {
    let widget: HomeWidget
    @ObservedObject var timer: TimerService
    let actions: HomeActions

    var body: some View {
        HomeTile(widget: widget, onTap: actions.openTimer, hint: t("Открыть таймер")) {
            // Полсекунды, как у полоски таймера: раз в секунду цифры
            // отставали бы от настоящего счёта на половину секунды.
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                if widget.size == .small {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            symbol
                            Spacer(minLength: 0)
                            playButton
                        }
                        Spacer(minLength: 0)
                        HomeValue(text: clock)
                    }
                } else {
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            HomeCaption(kind: widget.kind, title: timer.mode.title)
                            HomeValue(text: clock)
                        }
                        Spacer(minLength: 4)
                        if !timer.isClean {
                            HomeTileButton(symbol: "arrow.counterclockwise", hint: t("Сбросить")) {
                                timer.reset()
                            }
                        }
                        playButton
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
    }

    private var clock: String {
        TimerService.clock(timer.mode == .timer ? timer.remaining : timer.elapsed)
    }

    private var symbol: some View {
        Image(systemName: timer.mode == .timer ? "timer" : "stopwatch")
            .font(.system(size: NotchStyle.font(11), weight: .semibold))
            .foregroundStyle(widget.kind.tint)
    }

    private var playButton: some View {
        HomeTileButton(
            symbol: timer.isRunning ? "pause.fill" : "play.fill",
            hint: timer.isRunning ? t("Пауза") : t("Пуск"),
            diameter: widget.size == .small ? 24 : 26
        ) {
            timer.toggle()
        }
    }
}

// MARK: - Погода

struct WeatherWidget: View {
    let widget: HomeWidget
    @ObservedObject var weather: WeatherService

    var body: some View {
        HomeTile(widget: widget) {
            if let snapshot = weather.current {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Image(systemName: snapshot.condition.symbol)
                            .font(.system(size: NotchStyle.font(13), weight: .medium))
                            .foregroundStyle(snapshot.condition.tint)
                            .frame(height: NotchStyle.scaled(16))
                        Spacer(minLength: 0)
                        HomeValue(text: "\(snapshot.temperature)°")
                    }
                    if widget.size != .small {
                        VStack(alignment: .leading, spacing: 2) {
                            Spacer(minLength: 0)
                            Text(snapshot.condition.title)
                                .font(.system(size: NotchStyle.font(11.5), weight: .medium))
                                .lineLimit(1)
                            if let outlook = snapshot.outlook {
                                Text(tf("через %d ч %@", outlook.inHours, outlook.condition.title.lowercased()))
                                    .font(.system(size: NotchStyle.font(10.5)))
                                    .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.bottom, 3)
                        Spacer(minLength: 0)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tf("%@, %d°", snapshot.condition.title, snapshot.temperature))
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HomeCaption(kind: widget.kind)
                    HomeEmpty(text: t("Нет данных"))
                }
            }
        }
    }
}

// MARK: - Нагрузка

/// Процессор числом в малой плитке, три полоски — в широкой.
///
/// Опрос идёт, только пока плитка видна: его включает контроллер по тому же
/// правилу, что и для панели нагрузки, — иначе показатель стал бы той
/// нагрузкой, которую показывает.
struct MonitorWidget: View {
    let widget: HomeWidget
    @ObservedObject var monitor: MonitorService
    let actions: HomeActions

    var body: some View {
        let sample = monitor.sample
        HomeTile(widget: widget, onTap: actions.openMonitor, hint: t("Открыть нагрузку")) {
            if widget.size == .small {
                VStack(alignment: .leading, spacing: 0) {
                    HomeCaption(kind: widget.kind)
                    Spacer(minLength: 0)
                    HomeValue(text: percent(sample.cpu))
                }
            } else {
                VStack(spacing: 2) {
                    bar(t("Процессор"), sample.cpu)
                    bar(t("Память"), sample.memoryTotal > 0 ? sample.memoryShare : nil)
                    bar(t("Диск"), sample.diskTotal > 0 ? sample.diskShare : nil)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private func percent(_ share: Double?) -> String {
        guard let share else { return "—" }
        return "\(Int((share * 100).rounded()))%"
    }

    private func bar(_ title: String, _ share: Double?) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: NotchStyle.font(10.5), weight: .medium))
                .foregroundStyle(.white.opacity(NotchStyle.secondaryOpacity))
                .lineLimit(1)
                .frame(width: NotchStyle.scaled(62), alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule()
                        .fill(widget.kind.tint)
                        .frame(width: proxy.size.width * (share ?? 0))
                }
            }
            .frame(height: 4)
            Text(percent(share))
                .font(.system(size: NotchStyle.font(10.5), weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(NotchStyle.primaryOpacity))
                .frame(width: NotchStyle.scaled(32), alignment: .trailing)
        }
        .frame(height: NotchStyle.scaled(14))
    }
}

// MARK: - Батарея

struct BatteryWidget: View {
    let widget: HomeWidget
    @ObservedObject var battery: BatteryMonitor

    var body: some View {
        HomeTile(widget: widget) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: symbol)
                        .font(.system(size: NotchStyle.font(12), weight: .medium))
                        .foregroundStyle(battery.percentage <= 20 && !battery.isCharging
                                         ? Palette.negative : widget.kind.tint)
                    if battery.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: NotchStyle.font(9), weight: .bold))
                            .foregroundStyle(Palette.warning)
                    }
                }
                .frame(height: NotchStyle.scaled(16))
                Spacer(minLength: 0)
                HomeValue(text: battery.isPresent ? "\(battery.percentage)%" : "—")
            }
        }
    }

    private var symbol: String {
        guard battery.isPresent else { return "powerplug" }
        switch battery.percentage {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

// MARK: - Бодрость

/// Малая плитка — сама кнопка: нажатие зажигает или гасит чашку на срок
/// из настроек. В широкой переключатель отдельной кнопкой, а нажатие по
/// плитке открывает выбор срока.
struct CaffeineWidget: View {
    let widget: HomeWidget
    @ObservedObject var wake: WakeGuard
    @ObservedObject var settings: Settings
    let actions: HomeActions

    var body: some View {
        HomeTile(
            widget: widget,
            onTap: widget.size == .small ? toggle : actions.openAwake,
            hint: widget.size == .small
                ? (wake.isOn ? t("Выключить") : t("Включить"))
                : t("Выбрать срок")
        ) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if widget.size == .small {
                    VStack(alignment: .leading, spacing: 0) {
                        cup
                        Spacer(minLength: 0)
                        HomeValue(text: state(at: context.date), size: 15)
                    }
                } else {
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 2) {
                            HomeCaption(kind: widget.kind)
                            HomeValue(text: state(at: context.date), size: 17)
                        }
                        Spacer(minLength: 4)
                        HomeTileButton(
                            symbol: "power",
                            hint: wake.isOn ? t("Выключить") : t("Включить"),
                            action: toggle
                        )
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        }
    }

    private var cup: some View {
        Image(systemName: "cup.and.saucer.fill")
            .font(.system(size: NotchStyle.font(14), weight: .medium))
            .foregroundStyle(wake.isOn ? widget.kind.tint : .white.opacity(0.4))
            .frame(height: NotchStyle.scaled(16))
    }

    private func state(at date: Date) -> String {
        wake.isOn ? CaffeineChipView.label(endsAt: wake.endsAt, now: date) : t("Выкл.")
    }

    private func toggle() {
        if wake.isOn {
            actions.disableAwake()
        } else {
            actions.chooseAwakeLimit(settings.caffeineLimitMinutes)
        }
    }
}

// MARK: - Ярлык

/// Функция без данных, которые стоило бы показывать: значок и название.
struct LauncherWidget: View {
    let widget: HomeWidget
    let action: () -> Void

    var body: some View {
        HomeTile(widget: widget, onTap: action, hint: widget.kind.title) {
            VStack(spacing: 4) {
                Image(systemName: widget.kind.symbol)
                    .font(.system(size: NotchStyle.font(16), weight: .medium))
                    .foregroundStyle(widget.kind.tint)
                    .frame(height: NotchStyle.scaled(20))
                // В две строки, а не сжатием: «Надиктовать заметку» в клетку
                // не входит, и сжатое название стояло мельче соседнего.
                Text(widget.kind.title)
                    .font(.system(size: NotchStyle.font(10.5), weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
