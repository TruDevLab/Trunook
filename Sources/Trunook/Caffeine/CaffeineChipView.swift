import SwiftUI
import AppKit

/// Что показывает полоска горящей чашки.
///
/// Отдельным значением, а не ссылкой на службу: по нему считается ширина
/// острова, а расчёт состояния службами не пользуется — иначе его нельзя
/// было бы проверить тестом.
struct CaffeineChip: Equatable {
    /// Показывать ли часы. От этого зависит ширина полоски, и меняется она
    /// не чаще раза в час — остров не дёргается.
    let showsHours: Bool
    /// Срока нет: держим, пока не выключат. Показывать тогда нечего,
    /// и вместо цифр стоит знак бесконечности.
    let isEndless: Bool
}

/// Горящая чашка — полоска, расширяющая вырез вбок.
///
/// До неё о том, что экран удерживается, в свёрнутом вырезе не говорило
/// ничего: чашку включали и забывали, а потом удивлялись, почему ноутбук
/// не засыпает. Плашка о включении гаснет через несколько секунд, а само
/// удержание живёт часами — и всё это время о нём нужно напоминание,
/// а не воспоминание.
///
/// Устроена как полоска таймера: значок в левом крыле, срок в правом, между
/// ними зазор ровно по ширине аппаратного выреза. Иначе нельзя — в середине
/// острова видна сама чёлка, и рисовать там нечего.
struct CaffeineChipView: View {
    @ObservedObject var wake: WakeGuard
    let metrics: NotchMetrics
    /// Нажатие ведёт **сразу к выбору срока**, а не к меню функций: чашка
    /// на экране — это уже ответ на вопрос «включено ли», и единственное,
    /// что от неё ещё нужно, — переставить или снять срок.
    let onOpen: () -> Void

    static let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
    private static let symbolSize: CGFloat = 11

    /// Запас вокруг содержимого в боковой полосе — тот же, что у таймера
    /// и у отсчёта до встречи: учитывает вогнутый уголок формы, за которым
    /// тело острова начинается не от края.
    private static let sideMargin: CGFloat = 34

    /// Самая длинная форма записи. Восьмёрки, потому что в моноширинных
    /// цифрах они не у́же прочих, а мерить надо по худшему случаю.
    private static func widest(chip: CaffeineChip) -> String {
        if chip.isEndless { return endless }
        return chip.showsHours ? "8:88:88" : "88:88"
    }

    /// Без срока показывать нечего, а полоса всё равно нужна: она и есть
    /// напоминание. Знак не переводится и одинаково читается везде.
    static let endless = "∞"

    static func sideWidth(chip: CaffeineChip) -> CGFloat {
        TextMeasure.width(widest(chip: chip), font: font) + sideMargin
    }

    /// Ширина крыльев одинакова слева и справа: остров обязан оставаться
    /// отцентрованным по вырезу, иначе перестанет его закрывать.
    static func width(metrics: NotchMetrics, chip: CaffeineChip) -> CGFloat {
        metrics.notchWidth + 2 * sideWidth(chip: chip)
    }

    var body: some View {
        // Раз в полсекунды, как у таймера: цифры идут по секундам,
        // и обновление раз в секунду отставало бы на полсекунды —
        // было бы видно, что счёт запаздывает.
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let chip = wake.chip ?? CaffeineChip(showsHours: false, isEndless: true)
            HStack(spacing: 0) {
                side(chip) {
                    Image(systemName: "cup.and.saucer.fill")
                        .font(.system(size: Self.symbolSize, weight: .semibold))
                        .foregroundStyle(Palette.caffeine)
                }

                // Зазор ровно по ширине аппаратного выреза.
                Spacer(minLength: 0)
                    .frame(width: metrics.notchWidth)

                side(chip) {
                    Text(Self.label(endsAt: wake.endsAt, now: context.date))
                        .font(Font(Self.font))
                        // Моноширинные цифры: пропорциональные дёргали бы
                        // строку на каждой смене секунды.
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(width: Self.width(metrics: metrics, chip: chip),
                   height: metrics.notchHeight)
            // Нажимается вся полоса, а не только буквы: в середине её
            // закрывает сама чёлка, и мимо значка с цифрами попасть некуда.
            .contentShape(Rectangle())
            .onTapGesture(perform: onOpen)
            .notchHint(t("Бодрость"), bubble: t("Выбрать срок"))
        }
    }

    /// Сколько осталось.
    ///
    /// Отдельной функцией и на чистых значениях — чтобы проверить тестом:
    /// на глаз разницу между «осталось 0:00» и «срок вышел» не поймать,
    /// а вторая половина минуты в первой же секунде — обычная ошибка
    /// округления вниз.
    static func label(endsAt: Date?, now: Date) -> String {
        guard let endsAt else { return endless }
        let left = endsAt.timeIntervalSince(now)
        // Ноль, а не отрицательное: срок мог выйти раньше, чем полоска
        // успела погаснуть. Округление вверх делает сам `clock` — пока идёт
        // последняя секунда, её ещё не прошло, и «00:00» на живой чашке
        // читалось бы как «уже кончилось».
        return TimerService.clock(max(0, left))
    }

    /// Содержимое центрируется в своей полосе — так запас распределяется
    /// поровну между кромкой острова и краем выреза.
    private func side<Content: View>(
        _ chip: CaffeineChip,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(width: Self.sideWidth(chip: chip))
    }
}

extension WakeGuard {
    /// Описание полоски. `nil` — чашка погашена, и вырез остаётся свёрнутым.
    var chip: CaffeineChip? {
        guard isOn else { return nil }
        guard let endsAt else { return CaffeineChip(showsHours: false, isEndless: true) }
        return CaffeineChip(
            showsHours: endsAt.timeIntervalSinceNow >= 3600,
            isEndless: false
        )
    }
}
