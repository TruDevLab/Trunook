import SwiftUI

/// Миниатюра функции посреди веера — под подписью выбранного кружка.
///
/// Значок и имя отвечали на «как это называется», но не на «что там будет»:
/// «Полка», «Нагрузка», «Чистка клавиатуры» по одному слову не угадываются.
/// Миниатюра — схема самой панели в одну ладонь (сетка месяца, строки
/// буфера, кольцо таймера) и одна строка о том, что она делает.
///
/// Схема, а не живые данные: кольцо открывают на долю секунды, ведя руку,
/// и миниатюра должна читаться с одного взгляда, а не заставлять читать
/// чужой текст из буфера или заголовок заметки. Рисуется фигурами — без
/// снимков и без опросов служб.
struct QuickRingMiniature: View {
    let entry: HubEntry

    /// Размер карточки в полный рост. На коротком веере её уменьшают
    /// (`QuickRingLayout.miniatureScale`), а не перекладывают.
    static let size = CGSize(width: 150, height: 84)

    var body: some View {
        VStack(spacing: 6) {
            sketch
                .frame(width: 118, height: 46)
            Text(entry.blurb)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 8)
        .frame(width: Self.size.width, height: Self.size.height)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(entry.tint.opacity(0.35), lineWidth: 1)
        )
    }

    private var tint: Color { entry.tint }
    private var line: Color { .white.opacity(0.28) }
    private var faint: Color { .white.opacity(0.14) }

    @ViewBuilder
    private var sketch: some View {
        switch entry {
        case .assistant: assistant
        case .notes: notes
        case .calendar: calendar
        case .clipboard: clipboard
        case .shelf: shelf
        case .timer: timer
        case .monitor: monitor
        case .teleprompter: teleprompter
        case .news: news
        case .sites: sites
        case .caffeine: badge(symbol: "cup.and.saucer.fill", value: "1:00")
        case .keyboardLock: badge(symbol: "keyboard", value: "0:30", lock: true)
        case .voice: voice
        case .dictation: dictation
        }
    }

    // MARK: - Схемы

    /// Поле вопроса и две команды под ним.
    private var assistant: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles").font(.system(size: 8, weight: .bold)).foregroundStyle(tint)
                bar(width: 70, height: 4, color: line)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 14)
            .background(Capsule().fill(faint))
            ForEach(0..<2, id: \.self) { index in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(tint.opacity(0.8)).frame(width: 8, height: 8)
                    bar(width: index == 0 ? 54 : 40, height: 3, color: line)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .frame(height: 12)
            }
        }
    }

    /// Строки заметок: имя и под ним начало текста.
    private var notes: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                HStack(spacing: 5) {
                    Image(systemName: "note.text").font(.system(size: 7)).foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 2) {
                        bar(width: [52, 40, 60][index], height: 3, color: .white.opacity(0.45))
                        bar(width: [80, 70, 64][index], height: 2, color: faint)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 5)
                .frame(height: 13)
                .background(RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.06)))
            }
        }
    }

    /// Сетка месяца с выделенным днём и полоски дел рядом.
    private var calendar: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { column in
                            Circle()
                                .fill(row == 2 && column == 3 ? tint : (column > 4 ? faint : line))
                                .frame(width: 5, height: 5)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    HStack(spacing: 3) {
                        Capsule().fill(index == 0 ? tint : line).frame(width: 2, height: 9)
                        bar(width: [30, 24, 28][index], height: 3, color: index == 0 ? .white.opacity(0.5) : faint)
                    }
                }
            }
        }
    }

    /// Строки истории копирований с номерами горячих клавиш.
    private var clipboard: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                HStack(spacing: 5) {
                    Text("\(index + 1)")
                        .font(.system(size: 7, weight: .bold, design: .rounded))
                        .foregroundStyle(index == 0 ? tint : .white.opacity(0.4))
                        .frame(width: 8)
                    bar(width: [70, 54, 62][index], height: 3, color: index == 0 ? .white.opacity(0.5) : line)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 5)
                .frame(height: 13)
                .background(RoundedRectangle(cornerRadius: 3).fill(.white.opacity(index == 0 ? 0.12 : 0.05)))
            }
        }
    }

    /// Файлы плитками на полке.
    private var shelf: some View {
        HStack(spacing: 6) {
            ForEach(["doc.fill", "photo.fill", "doc.zipper"], id: \.self) { symbol in
                VStack(spacing: 3) {
                    Image(systemName: symbol)
                        .font(.system(size: 14))
                        .foregroundStyle(tint.opacity(0.9))
                    bar(width: 22, height: 2, color: line)
                }
                .frame(width: 32, height: 40)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.07)))
            }
        }
    }

    /// Кольцо отсчёта со временем.
    private var timer: some View {
        ZStack {
            Circle().stroke(faint, lineWidth: 4)
            Circle()
                .trim(from: 0, to: 0.68)
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("25:00")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(width: 42, height: 42)
    }

    /// Процессор, память, диск — три полосы.
    private var monitor: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array([0.62, 0.45, 0.8].enumerated()), id: \.offset) { index, share in
                HStack(spacing: 5) {
                    Image(systemName: ["cpu", "memorychip", "internaldrive"][index])
                        .font(.system(size: 7))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 9)
                    ZStack(alignment: .leading) {
                        Capsule().fill(faint).frame(width: 84, height: 5)
                        Capsule().fill(tint).frame(width: 84 * share, height: 5)
                    }
                }
            }
        }
    }

    /// Текст, который идёт вверх, — читаемая строка посередине.
    private var teleprompter: some View {
        VStack(spacing: 4) {
            bar(width: 80, height: 3, color: faint)
            bar(width: 96, height: 4, color: .white.opacity(0.8))
            bar(width: 88, height: 4, color: .white.opacity(0.55))
            bar(width: 70, height: 3, color: faint)
        }
        .overlay(alignment: .trailing) {
            Image(systemName: "arrow.up")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(tint)
                .offset(x: 12)
        }
    }

    /// Заголовок сводки и пункты под ним.
    private var news: some View {
        VStack(alignment: .leading, spacing: 4) {
            bar(width: 60, height: 4, color: tint)
            ForEach(0..<3, id: \.self) { index in
                HStack(spacing: 4) {
                    Circle().fill(.white.opacity(0.45)).frame(width: 3, height: 3)
                    bar(width: [84, 70, 78][index], height: 3, color: line)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 8)
    }

    /// Слежка за значением: кривая и цена, которая упала.
    private var sites: some View {
        HStack(spacing: 8) {
            Path { path in
                path.addLines([
                    .init(x: 0, y: 10), .init(x: 10, y: 14), .init(x: 20, y: 8),
                    .init(x: 30, y: 16), .init(x: 40, y: 22), .init(x: 50, y: 30),
                ])
            }
            .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .frame(width: 50, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.down").font(.system(size: 7, weight: .bold))
                    Text("−12%").font(.system(size: 9, weight: .bold, design: .rounded))
                }
                .foregroundStyle(tint)
                bar(width: 40, height: 3, color: line)
            }
        }
    }

    /// Голос: полосы громкости.
    private var voice: some View {
        HStack(spacing: 3) {
            ForEach(Array([10, 18, 28, 36, 24, 32, 16, 26, 12, 8].enumerated()), id: \.offset) { _, height in
                Capsule().fill(tint).frame(width: 4, height: CGFloat(height))
            }
        }
    }

    /// Диктовка: микрофон, и рядом ложатся строки текста.
    private var dictation: some View {
        HStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 16))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.white.opacity(0.08)))
            VStack(alignment: .leading, spacing: 4) {
                bar(width: 60, height: 3, color: .white.opacity(0.5))
                bar(width: 50, height: 3, color: line)
                HStack(spacing: 2) {
                    bar(width: 30, height: 3, color: line)
                    Capsule().fill(tint).frame(width: 1.5, height: 8)
                }
            }
        }
    }

    /// Значок и срок — у чашки и у чистки клавиатуры.
    private func badge(symbol: String, value: String, lock: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(tint)
                .overlay(alignment: .bottomTrailing) {
                    if lock {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .offset(x: 4, y: 3)
                    }
                }
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(.white.opacity(0.12)))
        }
    }

    private func bar(width: CGFloat, height: CGFloat, color: Color) -> some View {
        Capsule().fill(color).frame(width: width, height: height)
    }
}

extension HubEntry {
    /// Что делает функция — одна строка под миниатюрой.
    var blurb: String {
        switch self {
        case .assistant: return t("Вопрос модели и команды")
        case .notes: return t("Записи и поиск по ним")
        case .calendar: return t("Месяц и дела дня")
        case .clipboard: return t("История скопированного")
        case .shelf: return t("Файлы под рукой")
        case .timer: return t("Таймер и секундомер")
        case .monitor: return t("Процессор, память, диск")
        case .teleprompter: return t("Текст бежит под чёлкой")
        case .news: return t("Сводка новостей по темам")
        case .sites: return t("Слежка за ценой на сайте")
        case .caffeine: return t("Экран не гаснет")
        case .keyboardLock: return t("Замок на время чистки")
        case .voice: return t("Голосом, ответ вслух")
        case .dictation: return t("Голос текстом в заметку")
        }
    }
}
