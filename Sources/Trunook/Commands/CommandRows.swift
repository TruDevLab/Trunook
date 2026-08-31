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
    /// Модели всех включённых провайдеров. Пустой список — никто не ответил
    /// или моделей нет; выбирать тогда не из чего, и правая часть строки
    /// показывает только то, что уже выбрано.
    let models: [ModelRef]
    /// Модель из настроек — та, которой отвечают команды без своей.
    let defaultModel: ModelRef
    /// Какая строка подсвечена с клавиатуры.
    let highlighted: Int?
    /// У какой команды сейчас выбирают модель. `nil` — показываем команды.
    let choosingModelFor: Int?

    /// Модель команды — разобранная. Хранится она строкой вместе
    /// с провайдером; чей это сервер, по одному имени не узнать.
    private func model(of command: QuickCommand) -> ModelRef? {
        command.model.flatMap { ModelRef.parse($0, fallback: defaultModel.provider) }
    }

    let onRun: (QuickCommand) -> Void
    let onBeginChoosingModel: (QuickCommand) -> Void
    let onChooseModel: (String?) -> Void
    let onCancelChoosingModel: () -> Void

    // MARK: - Размеры

    /// Высота строки — общая ступень, а не своё число.
    ///
    /// Было 26, подобранных по месту, при 34 у истории буфера: тот же список,
    /// по которому так же целятся мышью, а высота разная — и читалось это
    /// как разная важность. Теперь обе берут `NotchStyle.rowHeight`
    /// и совпадают по построению, а не по договорённости.
    static var rowHeight: CGFloat { NotchStyle.rowHeight }

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
    static var modelWidth: CGFloat { NotchStyle.scaled(132) }

    // MARK: - Тело

    /// Якорь начала списка моделей. Выбор занимает место команд, а прокрутка
    /// при этом остаётся прежней — без якоря список моделей открывался бы
    /// с середины.
    private static let modelTopAnchor = "command-rows-model-top"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                // Группа стеклянных поверхностей: строки тянутся друг к другу
                // и читаются одним списком, а не стопкой отдельных плиток.
                //
                // Внутри прокрутки, а не вокруг неё, и это не мелочь.
                // `.frame(height:)` ниже ограничивает список четырьмя
                // строками; контейнер, поставленный над этим ограничением,
                // перестаёт передавать высоту вниз — панель уже ловили
                // на этом, когда группа обнимала её целиком: список отрисовал
                // все шесть строк, и полоса действий наехала на две последние.
                GlassGroup(spacing: Self.spacing) {
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
            }
            .frame(height: Self.height(rows: commands.count))
            // Стрелки водят подсветку по всему набору, а видно из него
            // четыре строки. Без прокрутки вслед за подсветкой пятая команда
            // выбиралась бы вслепую: подсветка стоит там, где её не видно,
            // и Enter запускает неизвестно что.
            //
            // Прокручиваем наименьшим движением (`anchor: nil`) — список
            // сдвигается на строку, а не перескакивает подсвеченным
            // в середину. Строки на месте, глазу не за чем гнаться.
            .onChange(of: highlighted) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: nil)
                }
            }
            .onChange(of: choosingModelFor) { _, choosing in
                if choosing != nil {
                    proxy.scrollTo(Self.modelTopAnchor, anchor: .top)
                } else if let highlighted {
                    proxy.scrollTo(highlighted, anchor: nil)
                }
            }
        }
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
            let chosen = model(of: command)
            let model = chosen ?? defaultModel
            // Приглушённее названия команды: модель — не то, что выбирают
            // в первую очередь, а уточнение к выбранному. Своя ярче
            // унаследованной: иначе не отличить «я так решил» от «как везде».
            let dim = chosen == nil ? NotchStyle.tertiaryOpacity : NotchStyle.secondaryOpacity
            Button { onBeginChoosingModel(command) } label: {
                HStack(spacing: 5) {
                    Spacer(minLength: 0)
                    ProviderIcon(provider: model.provider, size: NotchStyle.font(12))
                        .foregroundStyle(.white.opacity(dim))
                        // Значок не сжимается: имя рядом длинное, и первым
                        // делом SwiftUI ужимал бы именно его — ту самую
                        // картинку, ради которой всё и затевалось.
                        .layoutPriority(1)
                    Text(model.shortName)
                        .font(.system(size: NotchStyle.font(10)))
                        .foregroundStyle(.white.opacity(dim))
                        .lineLimit(1)
                        // С головы, а не с хвоста.
                        //
                        // Было наоборот: считалось, что хвост различает версии
                        // — `…coder:32b` говорит больше, чем `qwen2.5-c…`.
                        // На деле у длинных имён (`unsloth/gemma-4-E4B-it-qat`)
                        // от начала не оставалось ничего, и понять, что это
                        // за модель, было нельзя вовсе. Опознают модель
                        // по началу имени, а версию уточняют, открыв список.
                        .truncationMode(.tail)
                }
                .frame(width: Self.modelWidth, alignment: .trailing)
                .padding(.trailing, 8)
                .frame(height: Self.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .notchHint(
                t("Сменить модель"),
                bubble: tf("Модель команды: %@. Tab — следующая.", Self.full(chosen ?? defaultModel))
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
        let chosen = model(of: command)
        choiceRow(
            title: tf("Как в настройках (%@)", defaultModel.shortName),
            symbol: "gearshape",
            isOn: chosen == nil
        ) { onChooseModel(nil) }
        .id(Self.modelTopAnchor)

        ForEach(models, id: \.self) { model in
            // Здесь имя провайдера остаётся: строка выбора идёт во всю ширину
            // панели, места хватает обоим. Тесно было в строке команды —
            // там от названия модели после приставки не оставалось ничего,
            // и провайдера в ней несёт только значок.
            choiceRow(
                title: Self.full(model),
                provider: model.provider,
                isOn: chosen == model
            ) {
                onChooseModel(model.stored)
            }
        }

        if models.isEmpty {
            // Нажатие возвращает к списку команд: тупика быть не должно —
            // выбирать тут не из чего вовсе.
            Button(action: onCancelChoosingModel) {
                Text(t("Сервер не отвечает или моделей нет"))
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

    /// Строка выбора. `provider` — чья это модель: у него свой нарисованный
    /// значок, системного символа у провайдеров нет.
    private func choiceRow(
        title: String,
        symbol: String? = nil,
        provider: AIProvider? = nil,
        isOn: Bool,
        action: @escaping () -> Void
    ) -> some View {
        NotchTile(id: "model-\(title)", radius: NotchStyle.rowRadius) {
            Button(action: action) {
                HStack(spacing: 8) {
                    Group {
                        if isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: NotchStyle.font(10), weight: .semibold))
                        } else if let provider {
                            ProviderIcon(provider: provider, size: NotchStyle.font(13))
                        } else {
                            Image(systemName: symbol ?? "cube")
                                .font(.system(size: NotchStyle.font(10), weight: .semibold))
                        }
                    }
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
                        // С головы: опознают модель по началу имени.
                        .truncationMode(.tail)

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

    /// Имя вместе с тем, чей это сервер.
    ///
    /// Нужно там, где провайдеров несколько: одно и то же имя модели бывает
    /// у двух сразу, и выбор из двух одинаковых строк — не выбор.
    static func full(_ model: ModelRef) -> String {
        model.provider.title + " · " + model.shortName
    }
}
