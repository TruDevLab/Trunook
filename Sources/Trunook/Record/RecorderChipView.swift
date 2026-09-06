import SwiftUI
import AppKit

/// Что показывает полоска идущей записи.
///
/// Значением, а не ссылкой на службу: по нему считается ширина острова,
/// а расчёт состояния службами не пользуется — иначе его нельзя было бы
/// проверить тестом. Ровно как у таймера.
struct RecordingChip: Equatable {
    /// Пишем прямо сейчас. Иначе — сводим, расшифровываем или ждём модель.
    let isRecording: Bool
    /// Показывать ли часы. От этого зависит ширина, и меняется она не чаще
    /// раза в час — остров не дёргается.
    let showsHours: Bool
}

/// Идущая запись — полоска, расширяющая вырез вбок.
///
/// Устроена как полоска таймера: значок в левом крыле, время в правом,
/// между ними зазор ровно по ширине аппаратного выреза. В середине острова
/// видна сама чёлка, и рисовать там нечего.
///
/// **Одна полоска на всю работу, а не две.** Пока пишем — красная точка
/// и растущее время; пока сводим и расшифровываем — волна и время готовой
/// записи. Так видно, что работа не кончилась вместе с нажатием «стоп»:
/// заметка появится не сразу, и пустой вырез на этом месте читался бы
/// как «ничего не вышло».
struct RecorderChipView: View {
    @ObservedObject var recorder: RecorderService
    let metrics: NotchMetrics
    /// Нажатие по полоске останавливает запись.
    ///
    /// Отдельной панели у записи нет намеренно: показывать в ней нечего —
    /// время и так на виду, а всё управление это одно действие. Пока идёт
    /// обработка, нажатие не делает ничего: бросать на середине уже
    /// записанное нельзя.
    let onStop: () -> Void

    static let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
    private static let symbolSize: CGFloat = 11

    /// Запас вокруг содержимого — тот же, что у таймера: учитывает вогнутый
    /// уголок формы, за которым тело острова начинается не от края.
    private static let sideMargin: CGFloat = 34

    private static func widest(showsHours: Bool) -> String {
        showsHours ? "8:88:88" : "88:88"
    }

    static func sideWidth(showsHours: Bool) -> CGFloat {
        TextMeasure.width(widest(showsHours: showsHours), font: font) + sideMargin
    }

    /// Крылья одинаковы слева и справа: остров обязан оставаться
    /// отцентрованным по вырезу, иначе перестанет его закрывать.
    static func width(metrics: NotchMetrics, showsHours: Bool) -> CGFloat {
        metrics.notchWidth + 2 * sideWidth(showsHours: showsHours)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            HStack(spacing: 0) {
                side {
                    Image(systemName: recorder.phase.isRecording ? "record.circle" : "waveform")
                        .font(.system(size: Self.symbolSize, weight: .semibold))
                        .foregroundStyle(
                            recorder.phase.isRecording ? Palette.negative : Palette.positive
                        )
                }

                Spacer(minLength: 0)
                    .frame(width: metrics.notchWidth)

                side {
                    Text(TimerService.clock(seconds))
                        .font(Font(Self.font))
                        // Моноширинные цифры: пропорциональные дёргали бы
                        // строку на каждой смене секунды.
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(
                width: Self.width(metrics: metrics, showsHours: seconds >= 3600),
                height: metrics.notchHeight
            )
            // Нажимается вся полоса, а не только значок: в середине её
            // закрывает сама чёлка, и мимо попасть некуда.
            .contentShape(Rectangle())
            .onTapGesture(perform: onStop)
        }
    }

    /// Пока пишем — сколько уже идёт; после — сколько получилось.
    /// Замершее время объясняет, что запись кончилась, а работа нет.
    private var seconds: TimeInterval {
        recorder.phase.isRecording ? recorder.elapsed : recorder.lastDuration
    }

    private func side<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: Self.sideWidth(showsHours: seconds >= 3600))
    }
}

extension RecorderService {
    /// Описание полоски для расчёта состояния. `nil` — записи нет,
    /// и вырез остаётся свёрнутым.
    var chip: RecordingChip? {
        guard phase.isBusy else { return nil }
        let seconds = phase.isRecording ? elapsed : lastDuration
        return RecordingChip(isRecording: phase.isRecording, showsHours: seconds >= 3600)
    }
}
