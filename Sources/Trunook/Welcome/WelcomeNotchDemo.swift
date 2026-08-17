import SwiftUI

/// Демонстрация выреза: свёрнут → мини-вид → панель → история буфера →
/// полка → плашка о полке.
///
/// Показать это словами нельзя, а живьём пользователь ещё не знает, куда
/// вести курсор. Поэтому вырез проигрывает сам себя по кругу.
///
/// Вся анимация — чистая функция времени, без хранимого состояния: `@State`
/// в этом тулчейне недоступен, а `TimelineView` заодно не сбивает фазу при
/// перерисовке родителя.
struct WelcomeNotchDemo: View {
    static let size = CGSize(width: 480, height: 176)

    /// Длина круга. Подобрана так, чтобы каждое состояние успевало
    /// прочитаться, а ожидание следующего не тяготило.
    private static let loop: TimeInterval = 22.5

    private static let closedSize = CGSize(width: 168, height: 26)
    private static let previewSize = CGSize(width: 252, height: 46)
    /// Раскрытая панель заметно уже макета экрана: иначе она упирается
    /// в его края и перестаёт читаться как остров поверх рабочего стола.
    private static let expandedSize = CGSize(width: 348, height: 118)
    private static let clipboardSize = CGSize(width: 392, height: 126)
    private static let commandsSize = CGSize(width: 312, height: 132)
    private static let assistantSize = CGSize(width: 376, height: 134)
    /// Полка шире истории: плитки идут в ряд, а не строками.
    private static let shelfSize = CGSize(width: 404, height: 128)
    /// Плашка о полке — из тех, что выпадают из-под чёлки одной строкой.
    private static let chipSize = CGSize(width: 244, height: 42)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: Self.loop)
            VStack(spacing: 14) {
                stage(at: time)
                caption(at: time)
            }
        }
    }

    // MARK: - Фазы

    /// Моменты, в которые начинается каждая сцена. Числами по месту это
    /// было уже нечитаемо: сцен восемь, у каждой две границы, и сдвиг одной
    /// требовал пересчёта всех соседних.
    private enum Beat {
        static let preview = 1.3
        static let expanded = 3.2
        static let commands = 5.8
        static let assistant = 8.4
        static let clipboard = 11.6
        static let shelf = 14.4
        static let chip = 17.8
        static let collapse = 20.2
        /// Длительность перехода между сценами.
        static let fade = 0.6
    }

    /// Доля сцены: нарастает от своего момента и гаснет к следующему.
    private func phase(_ time: TimeInterval, from: Double, until: Double) -> Double {
        ramp(time, from, from + Beat.fade) * (1 - ramp(time, until, until + Beat.fade))
    }

    /// Насколько вырез раскрыт до мини-вида: 0 — свёрнут, 1 — мини-вид.
    private func openness(at time: TimeInterval) -> Double {
        phase(time, from: Beat.preview, until: Beat.collapse)
    }

    /// Насколько мини-вид разросся до полной панели. Держится до конца:
    /// все следующие сцены — это та же раскрытая панель с другим содержимым.
    private func expansion(at time: TimeInterval) -> Double {
        phase(time, from: Beat.expanded, until: Beat.collapse)
    }

    /// Меню быстрых команд: его вызывают клавишей, а не наведением.
    private func commandsness(at time: TimeInterval) -> Double {
        phase(time, from: Beat.commands, until: Beat.assistant)
    }

    /// Ответ модели — то, ради чего команду чаще всего и запускают.
    private func assistantness(at time: TimeInterval) -> Double {
        phase(time, from: Beat.assistant, until: Beat.clipboard)
    }

    private func clipboardness(at time: TimeInterval) -> Double {
        phase(time, from: Beat.clipboard, until: Beat.shelf)
    }

    /// Полка: сюда приводит файл, который ведут на чёлку.
    private func shelfness(at time: TimeInterval) -> Double {
        phase(time, from: Beat.shelf, until: Beat.chip)
    }

    /// Плашка о непустой полке — она остаётся, когда панель закрылась.
    private func chipness(at time: TimeInterval) -> Double {
        phase(time, from: Beat.chip, until: Beat.collapse)
    }

    /// Файл едет к чёлке и исчезает в ней: без него полка появлялась бы
    /// сама собой, а показать надо именно, откуда она берётся.
    private func fileTravel(at time: TimeInterval) -> Double {
        ramp(time, Beat.shelf - 0.7, Beat.shelf + 0.4)
    }

    private func fileVisibility(at time: TimeInterval) -> Double {
        ramp(time, Beat.shelf - 0.9, Beat.shelf - 0.5)
            * (1 - ramp(time, Beat.shelf + 0.3, Beat.shelf + 0.6))
    }

    /// Насколько написан ответ модели: строки прибавляются на глазах.
    /// Ответ, возникающий целиком, не отличить от заранее готового текста,
    /// а показать надо именно поток.
    private func answerProgress(at time: TimeInterval) -> Double {
        ramp(time, Beat.assistant + 0.5, Beat.clipboard - 0.6)
    }

    /// Курсор подходит к вырезу и уходит обратно.
    private func cursorPresence(at time: TimeInterval) -> Double {
        ramp(time, 0.8, 1.5) * (1 - ramp(time, Beat.collapse - 0.1, Beat.collapse + 0.6))
    }

    /// Круг нажатия: расходится за треть секунды и гаснет.
    private func clickPulse(at time: TimeInterval) -> Double {
        let start = Beat.expanded - 0.15
        guard time >= start, time < start + 0.45 else { return 0 }
        return (time - start) / 0.45
    }

    /// Плавный переход между двумя моментами: у линейного нарастания
    /// заметны углы на старте и финише, у этого — нет.
    private func ramp(_ value: Double, _ from: Double, _ to: Double) -> Double {
        guard to > from else { return value >= to ? 1 : 0 }
        let t = min(max((value - from) / (to - from), 0), 1)
        return t * t * (3 - 2 * t)
    }

    private func mix(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        a + (b - a) * CGFloat(t)
    }

    // MARK: - Сцена

    private func stage(at time: TimeInterval) -> some View {
        let open = openness(at: time)
        let grown = expansion(at: time)
        let cmd = commandsness(at: time)
        let ai = assistantness(at: time)
        let clip = clipboardness(at: time)
        let shelf = shelfness(at: time)
        let chip = chipness(at: time)

        // Каждая фаза подмешивается поверх предыдущей. Порядок тот же,
        // что и в рассказе, иначе размер прыгал бы через промежуточный.
        func blend(_ side: KeyPath<CGSize, CGFloat>) -> CGFloat {
            var value = mix(Self.closedSize[keyPath: side], Self.previewSize[keyPath: side], open)
            value = mix(value, Self.expandedSize[keyPath: side], grown)
            value = mix(value, Self.commandsSize[keyPath: side], cmd)
            value = mix(value, Self.assistantSize[keyPath: side], ai)
            value = mix(value, Self.clipboardSize[keyPath: side], clip)
            value = mix(value, Self.shelfSize[keyPath: side], shelf)
            return mix(value, Self.chipSize[keyPath: side], chip)
        }

        let width = blend(\.width)
        let height = blend(\.height)

        return ZStack(alignment: .top) {
            screen
            draggedFile(at: time)
            notch(width: width, height: height, open: open, grown: grown, cmd: cmd,
                  ai: ai, clip: clip, shelf: shelf, chip: chip, time: time)
            cursor(at: time, notchHeight: height)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    /// Файл, который ведут на чёлку. Едет снизу вверх и гаснет, войдя в неё.
    private func draggedFile(at time: TimeInterval) -> some View {
        let travel = fileTravel(at: time)
        return RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.white.opacity(0.9))
            .frame(width: 22, height: 28)
            .overlay(
                Image(systemName: "doc.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WelcomePalette.violet)
            )
            .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
            .offset(x: mix(52, 8, travel), y: mix(128, 26, travel))
            .opacity(fileVisibility(at: time))
    }

    /// Верх экрана: полоса меню и намёк на обои — чтобы вырез читался как
    /// часть экрана, а не как плашка, висящая в пустоте.
    private var screen: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.13, green: 0.12, blue: 0.22),
                        Color(red: 0.07, green: 0.09, blue: 0.16),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
            .overlay(alignment: .topTrailing) { menuBarIcons }
            .overlay(alignment: .topLeading) { menuBarTitle }
    }

    private var menuBarIcons: some View {
        HStack(spacing: 7) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(index == 3 ? 0.5 : 0.26))
                    .frame(width: index == 3 ? 9 : 8, height: 8)
            }
        }
        .padding(.trailing, 14)
        .padding(.top, 9)
    }

    private var menuBarTitle: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.white.opacity(0.35)).frame(width: 8, height: 8)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.white.opacity(0.22))
                .frame(width: 26, height: 6)
        }
        .padding(.leading, 14)
        .padding(.top, 10)
    }

    // MARK: - Вырез

    private func notch(width: CGFloat, height: CGFloat, open: Double, grown: Double, cmd: Double,
                       ai: Double, clip: Double, shelf: Double, chip: Double, time: TimeInterval) -> some View {
        let shape = NotchShape(topRadius: 7, bottomRadius: min(16, height / 2))
        return ZStack {
            shape.fill(Color.black)
            // `stroke`, а не `strokeBorder`: NotchShape не `InsettableShape`.
            shape.stroke(
                Color.white.opacity(0.07 + 0.1 * open),
                lineWidth: 0.75
            )
            notchContent(width: width, height: height, open: open, grown: grown, cmd: cmd,
                         ai: ai, clip: clip, shelf: shelf, chip: chip, time: time)
            clickRing(at: time)
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        // Свечение появляется только когда вырезом пользуются: свёрнутый
        // он должен быть неотличим от аппаратной чёлки.
        .shadow(color: WelcomePalette.cyan.opacity(0.35 * open), radius: 18)
    }

    /// Содержимому жёстко задан размер самой чёлки, и лишнее обрезается.
    ///
    /// Без этого раскрытая панель — она выше промежуточных состояний —
    /// растила бы `ZStack`, чёрная фигура тянулась бы за ней, а `frame`
    /// центрировал бы переросшее содержимое: чёлка вылезала вверх поверх
    /// заголовка и переставала раскрываться из мини-вида.
    private func notchContent(width: CGFloat, height: CGFloat, open: Double, grown: Double, cmd: Double,
                              ai: Double, clip: Double, shelf: Double, chip: Double, time: TimeInterval) -> some View {
        let inner = max(width - 32, 1)
        let box = max(height, 1)
        // Панель гаснет под каждой следующей сценой отдельно: её собственный
        // признак поднят до самого конца, и без вычитания она проступала бы
        // сквозь меню команд, ответ модели и полку.
        let later = (1 - cmd) * (1 - ai) * (1 - clip) * (1 - shelf) * (1 - chip)
        return ZStack {
            previewContent(time: time)
                .frame(width: inner, height: box)
                .opacity(open * (1 - grown))
            expandedContent(time: time)
                .frame(width: inner, height: box)
                .opacity(grown * later)
            commandsContent
                .frame(width: inner, height: box)
                .opacity(cmd)
            assistantContent(time: time)
                .frame(width: inner, height: box)
                .opacity(ai)
            clipboardContent
                .frame(width: inner, height: box)
                .opacity(clip * (1 - shelf) * (1 - chip))
            shelfContent
                .frame(width: inner, height: box)
                .opacity(shelf * (1 - chip))
            shelfChipContent
                .frame(width: inner, height: box)
                .opacity(chip)
        }
        .frame(width: width, height: box)
        .clipped()
    }

    /// Мини-вид: обложка, название и столбики эквалайзера.
    private func previewContent(time: TimeInterval) -> some View {
        HStack(spacing: 9) {
            artwork(side: 24)
            VStack(alignment: .leading, spacing: 3) {
                bar(width: 74, height: 5, opacity: 0.8)
                bar(width: 46, height: 4, opacity: 0.4)
            }
            Spacer(minLength: 0)
            equalizer(time: time, height: 14)
        }
    }

    /// Панель целиком: обложка крупнее, кнопки перемотки, строка встречи.
    private func expandedContent(time: TimeInterval) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 11) {
                artwork(side: 44)
                VStack(alignment: .leading, spacing: 5) {
                    bar(width: 108, height: 6, opacity: 0.85)
                    bar(width: 68, height: 5, opacity: 0.4)
                    progressLine
                }
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    control("backward.fill", size: 11)
                    control("pause.fill", size: 14)
                    control("forward.fill", size: 11)
                }
            }
            HStack(spacing: 8) {
                Circle().fill(WelcomePalette.mint).frame(width: 6, height: 6)
                bar(width: 96, height: 5, opacity: 0.45)
                Spacer(minLength: 0)
                Capsule()
                    .fill(WelcomePalette.cyan.opacity(0.22))
                    .frame(width: 62, height: 15)
                    .overlay(
                        Text(t("Войти"))
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundStyle(WelcomePalette.cyan)
                    )
            }
        }
        .padding(.vertical, 14)
    }

    /// История буфера: шапка и три строки с номерами. Настоящий список
    /// длиннее и прокручивается — здесь важно показать сам вид.
    private var clipboardContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                Text(t("Буфер обмена"))
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer(minLength: 0)
                Text("⌃⌥V")
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }
            ForEach(0..<3, id: \.self) { index in
                HStack(spacing: 7) {
                    Text("\(index + 1)")
                        .font(.system(size: 7.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 9)
                    Image(systemName: index == 1 ? "photo" : "text.alignleft")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.4))
                    bar(width: [124, 78, 152][index], height: 4.5, opacity: 0.7)
                    Spacer(minLength: 0)
                    bar(width: 34, height: 3.5, opacity: 0.22)
                }
                .padding(.horizontal, 6)
                .frame(height: 21)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.07)))
            }
        }
        .padding(.vertical, 12)
    }

    /// Меню быстрых команд: шапка с сочетанием и шесть слотов.
    private var commandsContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.2x2.fill")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                Text(t("Команды"))
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer(minLength: 0)
                Text("⌥⌘Space")
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }
            VStack(spacing: 5) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { column in
                            commandSlot(row * 3 + column)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 11)
    }

    /// Первый слот — запрос к модели: он же продолжает рассказ следующей
    /// сценой, поэтому выделен цветом и подписан значком искры.
    private func commandSlot(_ index: Int) -> some View {
        let symbols = ["sparkles", "folder.fill", "safari.fill",
                       "app.fill", "terminal.fill", "link"]
        let isAssistant = index == 0
        return HStack(spacing: 5) {
            Image(systemName: symbols[index])
                .font(.system(size: 9))
                .foregroundStyle(isAssistant ? WelcomePalette.violet : Color.white.opacity(0.45))
            bar(width: isAssistant ? 46 : 38, height: 4, opacity: isAssistant ? 0.75 : 0.4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(width: 88, height: 26)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isAssistant ? WelcomePalette.violet.opacity(0.18) : .white.opacity(0.07))
        )
    }

    /// Ответ модели: пишется в вырезе строка за строкой, снизу — действия.
    private func assistantContent(time: TimeInterval) -> some View {
        let written = answerProgress(at: time)
        // Строки прибавляются по очереди, последняя дописывается на глазах.
        let lines: [CGFloat] = [188, 164, 202, 138]
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(WelcomePalette.violet)
                Text(t("Ответ модели"))
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 5) {
                ForEach(0..<lines.count, id: \.self) { index in
                    let share = min(max(written * Double(lines.count) - Double(index), 0), 1)
                    bar(width: lines[index] * CGFloat(share), height: 4.5, opacity: 0.62)
                        .frame(width: lines[index], alignment: .leading)
                }
            }
            // Без распорки: содержимому снаружи задана жёсткая высота, и
            // распорка внутри неё уходила в отрицательную — строка действий
            // оказывалась перевёрнутой.
            HStack(spacing: 5) {
                answerAction(t("Ответить"))
                answerAction(t("Скопировать"))
                answerAction(t("Вставить"))
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.vertical, 11)
    }

    private func answerAction(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 7.5, weight: .semibold, design: .rounded))
            .foregroundStyle(WelcomePalette.cyan.opacity(0.85))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(WelcomePalette.cyan.opacity(0.16)))
    }

    /// Полка: шапка со счётчиком и ряд плиток. Настоящая шире и умеет
    /// прокручиваться — здесь важно показать сам вид.
    private var shelfContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "tray.full")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                Text(t("Полка"))
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                Text("4")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 0.5)
                    .background(Capsule().fill(.white.opacity(0.1)))
                Spacer(minLength: 0)
                Text("⌃⌥S")
                    .font(.system(size: 7, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { index in
                    shelfTile(index)
                }
            }
        }
        .padding(.vertical, 11)
    }

    private func shelfTile(_ index: Int) -> some View {
        let symbols = ["doc.fill", "photo.fill", "folder.fill", "film.fill"]
        return VStack(spacing: 4) {
            Image(systemName: symbols[index])
                .font(.system(size: 15))
                .foregroundStyle(WelcomePalette.cyan.opacity(0.85))
            bar(width: [42, 34, 46, 38][index], height: 4, opacity: 0.55)
            bar(width: 22, height: 3, opacity: 0.22)
        }
        .frame(width: 82, height: 62)
        .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.07)))
    }

    /// Плашка о полке: она остаётся на чёлке, пока файлы не разобрали.
    private var shelfChipContent: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(.white.opacity(0.12))
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: "tray.full")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WelcomePalette.cyan)
                )
            Text(tf("На полке файлов: %d", 4))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            Spacer(minLength: 0)
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    private func artwork(side: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [WelcomePalette.violet, WelcomePalette.cyan],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: side, height: side)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: side * 0.4, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.55))
            )
    }

    private func bar(width: CGFloat, height: CGFloat, opacity: Double) -> some View {
        Capsule()
            .fill(Color.white.opacity(opacity))
            .frame(width: width, height: height)
    }

    private var progressLine: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.16)).frame(width: 132, height: 3)
            Capsule().fill(WelcomePalette.cyan).frame(width: 52, height: 3)
        }
    }

    private func control(_ symbol: String, size: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.85))
    }

    /// Столбики пляшут по синусоидам с разными периодами: одинаковые
    /// выглядели бы как шагающий строй, а не как звук.
    private func equalizer(time: TimeInterval, height: CGFloat) -> some View {
        HStack(alignment: .bottom, spacing: 2.5) {
            ForEach(0..<4, id: \.self) { index in
                let speed = 3.1 + Double(index) * 0.7
                let level = 0.35 + 0.65 * abs(sin(time * speed + Double(index)))
                Capsule()
                    .fill(WelcomePalette.cyan.opacity(0.9))
                    .frame(width: 2.5, height: height * CGFloat(level))
            }
        }
        .frame(height: height, alignment: .bottom)
    }

    // MARK: - Курсор и нажатие

    private func cursor(at time: TimeInterval, notchHeight: CGFloat) -> some View {
        let presence = cursorPresence(at: time)
        // Курсор идёт снизу к вырезу и на раскрытой панели чуть опускается —
        // так видно, что он остаётся внутри, а не уходит следом за краем.
        let travel = mix(96, 10, presence)
        return Image(systemName: "cursorarrow")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
            .offset(x: 14, y: notchHeight * 0.55 + travel)
            .opacity(presence)
    }

    @ViewBuilder
    private func clickRing(at time: TimeInterval) -> some View {
        let pulse = clickPulse(at: time)
        if pulse > 0 {
            Circle()
                .strokeBorder(WelcomePalette.cyan.opacity(0.8 * (1 - pulse)), lineWidth: 1.5)
                .frame(width: 20 + 46 * pulse, height: 20 + 46 * pulse)
                .offset(x: 14, y: 12)
        }
    }

    // MARK: - Подпись

    private func caption(at time: TimeInterval) -> some View {
        let text: String
        if time < Beat.preview {
            text = t("Свёрнут — обычная чёлка")
        } else if time < Beat.expanded {
            text = t("Курсор наведён — мини-вид")
        } else if time < Beat.commands {
            text = t("Нажатие — панель целиком")
        } else if time < Beat.assistant {
            text = t("⌥⌘Space — быстрые команды")
        } else if time < Beat.clipboard {
            text = t("Ответ модели пишется прямо в вырезе")
        } else if time < Beat.shelf {
            text = t("⌃⌥V — история буфера обмена")
        } else if time < Beat.chip {
            text = t("Файл на чёлку — он ложится на полку")
        } else if time < Beat.collapse {
            text = t("Плашка помнит, что файлы отложены")
        } else {
            text = t("Курсор ушёл — вырез свернулся")
        }
        return Text(text)
            .font(.system(size: 11.5, weight: .medium, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.5))
            .animation(.easeInOut(duration: 0.25), value: text)
    }
}
