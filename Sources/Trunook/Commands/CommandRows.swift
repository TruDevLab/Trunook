import SwiftUI

/// Список команд под полем вопроса.
///
/// Был сеткой плиток в отдельной накладке — меню, которое открывалось своей
/// клавишей и жило само по себе. Меню вызывалось вслепую и потому держало
/// ровно шесть мест: растущая сетка сводила бы на нет саму идею попасть
/// в нужное действие не глядя.
///
/// Здесь всё наоборот: список стоит под захваченным текстом и под полем
/// вопроса, его читают глазами, и ограничивать число команд стало незачем.
/// Отсюда и строки вместо плиток — у строки есть правый край, куда помещается
/// имя модели, а у плитки его нет.
struct CommandRows: View {
    let commands: [QuickCommand]
    /// Модели, установленные в Ollama. Пустой список — Ollama не отвечает
    /// или моделей нет; выбирать тогда не из чего, и правая часть строки
    /// показывает только то, что уже выбрано.
    let models: [String]
    /// Модель из настроек — та, которой отвечают команды без своей.
    let defaultModel: String
    /// Какая строка подсвечена с клавиатуры.
    let highlighted: Int?
    /// У какой команды сейчас выбирают модель. `nil` — показываем команды.
    let choosingModelFor: Int?

    let onRun: (QuickCommand) -> Void
    let onBeginChoosingModel: (QuickCommand) -> Void
    let onChooseModel: (String?) -> Void
    let onCancelChoosingModel: () -> Void

    // MARK: - Размеры

    /// Высота строки. Как у истории буфера: это тот же список, по которому
    /// целятся мышью, и разная высота у соседних панелей читалась бы как
    /// разная важность.
    static var rowHeight: CGFloat { NotchStyle.scaled(26) }

    static var spacing: CGFloat { NotchStyle.rowSpacing }

    /// Сколько строк займёт список из такого числа команд.
    ///
    /// Не меньше одной: пустой список — это тоже строка, «команд пока нет».
    /// Без неё в панели оставалась бы дыра, по которой не понять, сломалось
    /// что-то или команд просто не завели.
    static func visibleRows(for count: Int) -> Int {
        min(max(1, count), QuickCommands.visibleRows)
    }

    /// Высота списка по числу команд.
    ///
    /// Считается по числу, а не по самим командам, потому что тем же расчётом
    /// пользуется потолок окна — а у потолка команд нет и быть не может.
    static func height(rows count: Int) -> CGFloat {
        let rows = visibleRows(for: count)
        return CGFloat(rows) * rowHeight + CGFloat(rows - 1) * spacing
    }

    /// Сколько места отдано имени модели.
    ///
    /// Постоянная доля, а не по содержимому: имена моделей бывают и `phi3`,
    /// и `qwen2.5-coder:32b-instruct-q4_K_M`, и колонка, тянущаяся
    /// за длинным, съела бы название команды целиком. Длинное имя обрезается
    /// с головы — хвост у моделей и различает версии.
    static var modelWidth: CGFloat { NotchStyle.scaled(116) }

    // MARK: - Тело

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Self.spacing) {
                if let id = choosingModelFor, let command = commands.first(where: { $0.id == id }) {
                    modelChoices(for: command)
                } else if commands.isEmpty {
                    emptyRow
                } else {
                    ForEach(commands) { command in
                        row(command)
                    }
                }
            }
        }
        .frame(height: Self.height(rows: commands.count))
    }

    // MARK: - Строка команды

    private func row(_ command: QuickCommand) -> some View {
        let isHighlighted = command.id == highlighted
        return NotchTile(id: "command-\(command.id)", radius: NotchStyle.rowRadius) {
            HStack(spacing: 0) {
                // Нажатие живёт внутри плитки, а не вокруг неё: имя модели
                // обязано быть отдельной кнопкой, а кнопка, вложенная
                // в кнопку, нажатий не получает — она запускала бы команду
                // вместо того, чтобы сменить модель.
                Button { onRun(command) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: command.effectiveSymbol)
                            .font(.system(size: NotchStyle.font(11), weight: .medium))
                            .foregroundStyle(Palette.assistant)
                            .frame(width: 16)

                        Text(command.title)
                            .font(.system(size: NotchStyle.font(11.5)))
                            .foregroundStyle(.white.opacity(NotchStyle.primaryOpacity))
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer(minLength: 8)
                    }
                    .padding(.leading, 8)
                    .frame(height: Self.rowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .notchHint(command.title, bubble: hint(for: command))

                modelButton(command)
            }
        }
        // Подсветка с клавиатуры — обводкой, а не заливкой: заливка у плитки
        // уже занята наведением, и две подсветки одной заливкой сливались бы
        // в одну. Строка бывает подсвечена клавишей и мышью одновременно.
        .overlay(
            RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
                .strokeBorder(
                    isHighlighted ? Palette.assistant.opacity(0.9) : .clear,
                    lineWidth: 1.5
                )
        )
        .animation(.easeOut(duration: 0.12), value: isHighlighted)
    }

    /// Что говорит плашка под чёлкой при наведении на строку.
    ///
    /// Сочетание — если оно у команды есть: список заодно ему и учит,
    /// иначе подсмотреть его негде, кроме настроек.
    private func hint(for command: QuickCommand) -> String {
        guard let display = command.hotKey?.display else { return command.title }
        return command.title + " · " + display
    }

    // MARK: - Модель в правой части строки

    @ViewBuilder
    private func modelButton(_ command: QuickCommand) -> some View {
        if command.kind.usesModel {
            Button { onBeginChoosingModel(command) } label: {
                Text(Self.shortName(command.model ?? defaultModel))
                    .font(.system(size: NotchStyle.font(10)))
                    // Приглушённее названия команды: это не то, что выбирают
                    // в первую очередь, а уточнение к выбранному. Своя модель
                    // ярче унаследованной — иначе не отличить «я так решил»
                    // от «как везде».
                    .foregroundStyle(
                        .white.opacity(
                            command.model == nil
                                ? NotchStyle.tertiaryOpacity
                                : NotchStyle.secondaryOpacity
                        )
                    )
                    .lineLimit(1)
                    // С головы, а не с хвоста: у моделей хвост и различает
                    // версии — `…coder:32b` говорит больше, чем `qwen2.5-c…`.
                    .truncationMode(.head)
                    .frame(width: Self.modelWidth, alignment: .trailing)
                    .padding(.trailing, 8)
                    .frame(height: Self.rowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .notchHint(
                t("Сменить модель"),
                bubble: tf("Модель команды: %@. Tab — следующая.", command.model ?? defaultModel)
            )
        } else {
            // Место всё равно занято: без него название команды без модели
            // тянулось бы шире соседних, и список перестал бы читаться
            // колонками.
            Color.clear
                .frame(width: Self.modelWidth + 8, height: Self.rowHeight)
        }
    }

    // MARK: - Выбор модели

    /// Список моделей — на месте списка команд, а не всплывающим окном.
    ///
    /// Всплывающее здесь негде показать: панель висит вплотную к верхней
    /// кромке экрана, вниз её содержимое обрезается окном, а системный `Picker`
    /// вдобавок принёс бы в вырез системный материал и системную синеву —
    /// единственное место, где они вообще появились бы. Занять на два удара
    /// то же место дешевле: высота списка не меняется, и панель не дёргается.
    @ViewBuilder
    private func modelChoices(for command: QuickCommand) -> some View {
        choiceRow(
            title: tf("Как в настройках (%@)", Self.shortName(defaultModel)),
            symbol: "gearshape",
            isOn: command.model == nil
        ) { onChooseModel(nil) }

        ForEach(models, id: \.self) { model in
            choiceRow(title: Self.shortName(model), symbol: "cube", isOn: command.model == model) {
                onChooseModel(model)
            }
        }

        if models.isEmpty {
            // Нажатие возвращает к списку команд: тупика быть не должно —
            // выбирать тут не из чего вовсе.
            Button(action: onCancelChoosingModel) {
                Text(t("Ollama не отвечает или моделей нет"))
                    .font(.system(size: NotchStyle.font(11)))
                    .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .frame(height: Self.rowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .notchHint(t("Вернуться к командам"))
        }
    }

    private func choiceRow(
        title: String,
        symbol: String,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        NotchTile(id: "model-\(title)", radius: NotchStyle.rowRadius) {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: isOn ? "checkmark" : symbol)
                        .font(.system(size: NotchStyle.font(10), weight: .semibold))
                        .foregroundStyle(
                            isOn ? Palette.assistant : .white.opacity(NotchStyle.tertiaryOpacity)
                        )
                        .frame(width: 16)

                    Text(title)
                        .font(.system(size: NotchStyle.font(11.5)))
                        .foregroundStyle(.white.opacity(
                            isOn ? NotchStyle.primaryOpacity : NotchStyle.secondaryOpacity
                        ))
                        .lineLimit(1)
                        .truncationMode(.head)

                    Spacer(minLength: 8)
                }
                .padding(.horizontal, 8)
                .frame(height: Self.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .notchHint(title)
            // Состояние отдельным значением: имя, меняющееся вместе
            // с выбором, диктор прочтёт как другую строку, а не как ту же
            // в другом состоянии.
            .accessibilityValue(isOn ? t("выбрано") : "")
        }
    }

    // MARK: - Пустой список

    private var emptyRow: some View {
        Text(t("Команд пока нет — задайте их в настройках"))
            .font(.system(size: NotchStyle.font(11)))
            .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .frame(height: Self.rowHeight)
    }

    // MARK: - Имя модели

    /// Обрезает у имени то, что и так одинаково у всех.
    ///
    /// Ollama называет модели `library/gemma3:4b`, и приставка `library/`
    /// стоит у большинства — она не различает ничего, а место отнимает
    /// у того, что различает.
    static func shortName(_ model: String) -> String {
        guard let slash = model.lastIndex(of: "/") else { return model }
        return String(model[model.index(after: slash)...])
    }
}
