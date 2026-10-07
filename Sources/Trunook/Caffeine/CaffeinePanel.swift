import SwiftUI

/// Выбор срока для чашки кофе.
///
/// Раньше срок жил только в настройках, и неудобно это было ровно там, где
/// чашкой и пользуются: включают её под конкретное дело — досмотреть,
/// дочитать, дождаться сборки, — и срок у каждого дела свой. Ходить за ним
/// в отдельное окно, чтобы поменять число и вернуться, дороже самого дела.
///
/// Поэтому нажатие по чашке больше не переключает удержание вслепую,
/// а открывает этот выбор. Настройка при этом не лишняя: она задаёт,
/// что предложено по умолчанию.
///
/// Отдельной накладкой, а не строкой внутри раскрытой панели: у той внизу
/// расписание и музыка, и вставленный между ними ряд кнопок читался бы
/// как часть расписания.
struct CaffeinePanel: View {
    @ObservedObject var wake: WakeGuard
    /// Переключатель «С закрытой крышкой» читает настройку.
    @ObservedObject var settings: Settings
    let metrics: NotchMetrics
    let onChoose: (Int) -> Void
    let onDisable: () -> Void
    let onClose: () -> Void

    static var width: CGFloat { NotchStyle.scaled(440) }
    static let bodyPadding: CGFloat = NotchStyle.bottomPadding

    private static var statusHeight: CGFloat { NotchStyle.scaled(22) }
    private static let clockHeight: CGFloat = 46
    private static var rowHeight: CGFloat { NotchStyle.rowHeight }

    /// Шкала — как у таймера, только деление в пять минут и длинное
    /// на каждые полчаса: срок чашки меряют часами, и по минуте на деление
    /// до двух часов пришлось бы тянуть через полтора метра.
    static let range = 5...480
    static let unit = 5
    static let majorEvery = 6
    /// Прибавка горящей чашке — как «+1 мин» у таймера, только в масштабе
    /// её сроков.
    static let extendMinutes = 30

    static func height(notchHeight: CGFloat) -> CGFloat {
        NotchStyle.height(
            notchHeight: notchHeight,
            contentHeight: statusHeight + clockHeight + TimerDial.height + rowHeight
                + NotchStyle.gridSpacing * 3
        )
    }

    var body: some View {
        NotchPanel(metrics: metrics, width: Self.width, bodyPadding: Self.bodyPadding) {
            NotchPanelTitle(
                // Контурная, как во всех шапках: рядом стоит слово, узнавание
                // держится на нём. Залитая была здесь единственным
                // нарушением правила на всё приложение — см. `NotchStyle`,
                // «Начертание значков». В самом вырезе чашка залитая:
                // там она стоит одна и опереться ей не на что.
                symbol: "cup.and.saucer",
                title: t("Бодрость"),
                tint: Palette.caffeine
            )
        } trailing: {
            NotchPanelButton(symbol: "xmark", hint: t("Закрыть"), action: onClose)
        } content: {
            VStack(spacing: NotchStyle.gridSpacing) {
                status
                clock
                controls
            }
        }
    }

    // MARK: - Что происходит сейчас

    /// Строка состояния и переключатель закрытой крышки справа.
    private var status: some View {
        HStack(spacing: 8) {
            Text(wake.isOn
                 ? (wake.endsAt == nil ? t("Экран не гаснет — без ограничения") : t("Экран не гаснет"))
                 : t("Экран гаснет как обычно"))
                .font(.system(size: NotchStyle.rowFontSize))
                .foregroundStyle(.white.opacity(
                    wake.isOn ? NotchStyle.primaryOpacity : NotchStyle.secondaryOpacity
                ))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            lidSwitch
        }
        .frame(height: Self.statusHeight)
    }

    /// «С закрытой крышкой»: Mac не засыпает, и когда крышку закрыли.
    /// Пароль администратора спросит сама macOS — при включении чашки
    /// и при выключении (`LidSleep`). Горит цветом чашки, пока сон и правда
    /// выключен; включено, а пароля не дали — только обводка.
    private var lidSwitch: some View {
        let on = settings.caffeineLidClosed
        return Button { wake.setLidClosed(!on) } label: {
            Label(t("С закрытой крышкой"), systemImage: on ? "laptopcomputer.slash" : "laptopcomputer")
                .font(.system(size: NotchStyle.font(10), weight: .medium))
                .foregroundStyle(on ? Palette.caffeine : .white.opacity(NotchStyle.secondaryOpacity))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(wake.holdsLid ? Palette.caffeine.opacity(0.22) : .white.opacity(0.08)))
                .overlay(Capsule().strokeBorder(on ? Palette.caffeine.opacity(0.6) : .clear, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .fixedSize()
        .notchHint(on
            ? t("Mac не уснёт с закрытой крышкой — спросит пароль администратора")
            : t("Не засыпать и с закрытой крышкой"))
    }

    // MARK: - Цифры и шкала

    /// Выбранный на шкале срок — по умолчанию полчаса (`WakeGuard.defaultMinutes`).
    private var draftMinutes: Int {
        min(max(wake.draftMinutes, Self.range.lowerBound), Self.range.upperBound)
    }

    /// Шкалу везёт сама чашка, пока горит со сроком — как идущий таймер.
    private var isCounting: Bool { wake.isOn && wake.endsAt != nil }

    /// Цифры и шкала перерисовываются `TimelineView`, а не таймером службы:
    /// пока панель закрыта, обновлять нечего. Так же сделан таймер.
    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = wake.endsAt.map { max(0, $0.timeIntervalSince(context.date)) }
            VStack(spacing: NotchStyle.gridSpacing) {
                Text(isCounting
                     ? TimerService.clock(left ?? 0)
                     : TimerService.clock(TimeInterval(draftMinutes * 60)))
                    .font(.system(size: NotchStyle.font(34), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(wake.isOn ? Palette.caffeine : .white)
                    .contentTransition(.identity)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.clockHeight)
                TimerDial(
                    centerMinutes: isCounting ? (left ?? 0) / 60 : Double(draftMinutes),
                    range: isCounting ? 0...Self.range.upperBound : Self.range,
                    onScrub: isCounting ? nil : { wake.draftMinutes = $0 },
                    unit: Self.unit,
                    majorEvery: Self.majorEvery,
                    label: Self.dialLabel,
                    tint: Palette.caffeine
                )
            }
        }
    }

    /// Подпись под получасом: «30», «1 ч», «1:30».
    static func dialLabel(_ minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)" }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? tf("%d ч", hours) : "\(hours):\(String(format: "%02d", rest))"
    }

    // MARK: - Кнопки

    /// Включение и выключение — справа и цветом: жёлтая «Включить»,
    /// красная «Выключить». Это главное действие панели, и искать его
    /// среди сроков не должно приходиться. Слева — сроки.
    private var controls: some View {
        HStack(spacing: 6) {
            if wake.isOn {
                if isCounting {
                    action(tf("+%d мин", Self.extendMinutes), symbol: "plus") {
                        let left = (wake.endsAt?.timeIntervalSinceNow ?? 0) / 60
                        onChoose(Int(left.rounded(.up)) + Self.extendMinutes)
                    }
                } else {
                    action(tf("Ограничить: %@", Self.title(minutes: draftMinutes)), symbol: "timer") {
                        onChoose(draftMinutes)
                    }
                }
                Spacer(minLength: 0)
                power(t("Выключить"), symbol: "power", fill: Self.offTint, label: .white, action: onDisable)
            } else {
                action(t("Без срока"), symbol: "infinity") { onChoose(0) }
                Spacer(minLength: 0)
                power(t("Включить"), symbol: "play.fill", fill: Self.onTint, label: .black, action: { onChoose(draftMinutes) })
            }
        }
        .frame(height: Self.rowHeight)
    }

    /// Жёлтый «Включить» и красный «Выключить».
    static let onTint = Color(red: 1.0, green: 0.84, blue: 0.2)
    static var offTint: Color { Palette.negative }

    /// Главная кнопка — заливкой своего цвета, а не стеклом.
    private func power(
        _ title: String,
        symbol: String,
        fill: Color,
        label: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: NotchStyle.font(11), weight: .semibold))
                .foregroundStyle(label)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(fill))
                .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .fixedSize()
    }

    /// Ноль — «без срока». Круглые часы подписаны часами: «120 мин» человек
    /// про себя всё равно переводит в два часа.
    static func title(minutes: Int) -> String {
        guard minutes > 0 else { return t("Без срока") }
        guard minutes % 60 == 0 else {
            return minutes > 60 ? "\(minutes / 60):\(String(format: "%02d", minutes % 60))" : tf("%d мин", minutes)
        }
        return tf("%d ч", minutes / 60)
    }

    /// Кнопки — те же капсулы, что у таймера: одна и та же панель выбора
    /// времени не должна выглядеть в двух местах по-разному.
    private func action(
        _ title: String,
        symbol: String,
        isPrimary: Bool = false,
        tint: Color = .white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
            }
            .font(.system(size: NotchStyle.font(11), weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(isPrimary ? 0.22 : 0.12)))
        }
        .buttonStyle(PressableStyle())
        .fixedSize()
    }
}
