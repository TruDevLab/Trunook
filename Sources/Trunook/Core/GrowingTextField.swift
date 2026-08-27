import AppKit
import SwiftUI

/// Поле ввода, которое растёт вместе с набранным.
///
/// Вопрос модели был однострочным `NSTextField`, и это оказалось не мелким
/// неудобством, а тупиком: текст, переросший строку, уезжал за правый край
/// и **дальше не набирался вовсе** — курсор упирался в кромку, и человек
/// не видел ни начала своего вопроса, ни конца. Вопрос к модели длиннее
/// строки — не исключение, а обычный случай.
///
/// Отсюда всё устройство:
///
/// - **Enter отправляет, ⇧Enter переводит строку.** Порядок именно такой:
///   отправляют почти всегда, абзац нужен изредка — и клавиша без
///   модификатора достаётся частому.
/// - **Высота считается снаружи**, статической функцией, а не меряется
///   по факту. Панель висит под чёлкой, её размер задаёт окно, и окно должно
///   знать высоту **до** того, как поле будет построено. Тот же расчёт
///   спрашивает и вёрстка, и `NotchSizing` — как у области ответа.
/// - **Потолок в пять строк**, дальше прокрутка. Растущее без предела поле
///   закрыло бы пол-экрана, а панель уехать вниз не может — окно приклеено
///   к верхней кромке.
///
/// Не `RichTextView`: там оформленный текст, распознавание ссылок и своя
/// логика вставки — вопросу модели всё это не нужно, а Enter у него занят
/// отправкой, чего заметке как раз нельзя.
struct GrowingTextField: NSViewRepresentable {
    @Binding var text: String
    /// Ширина, по которой текст переносится. Нужна расчёту высоты: он идёт
    /// снаружи, и подсмотреть настоящую ширину поля ему негде.
    var textWidth: CGFloat
    /// Enter без модификаторов.
    ///
    /// Отправляет набранное — но только если в списке команд никто
    /// не подсвечен: с подсветкой Enter запускает её, и решает это сам
    /// обработчик, а не поле. Полю о списке знать нечего.
    var onSubmit: () -> Void

    /// ↑ и ↓ — вести подсветку по списку команд: −1 вверх, +1 вниз.
    ///
    /// Возврат `true` значит «нажатие забрали». Пока подсветка ведётся,
    /// стрелка принадлежит списку; в остальное время уходит тексту — в поле,
    /// выросшем до нескольких строк, ими водят курсор.
    var onMoveHighlight: ((Int) -> Bool)?

    /// ← и → — вести подсветку по действиям с ответом: −1 влево, +1 вправо.
    ///
    /// Забирать стрелки у поля можно только пока подсветка есть: в остальное
    /// время ими двигают курсор по набранному вопросу, и съедать их значило
    /// бы сломать обычную правку текста.
    var onMoveAnswerAction: ((Int) -> Bool)?

    /// Tab — сменить модель подсвеченной команды. `true` — забрали себе.
    ///
    /// Без подсветки Tab отдаётся системе: обход по элементам он здесь
    /// не делает, но и съедать его беспричинно незачем.
    var onCycleModel: (() -> Bool)?

    /// Esc — снять подсветку. `false` значит «подсветки не было»: тогда
    /// нажатие идёт дальше, и панель закрывает `NotchInput`.
    var onEscape: (() -> Bool)?

    static let font = NSFont.systemFont(ofSize: 12)

    /// Поле вокруг текста. Слева и справа — по капле больше, чем сверху
    /// и снизу: скруглённый торец капсулы съедает край строки.
    static let inset = CGSize(width: 12, height: 6)

    /// Высота одной строки — она же наименьшая высота поля.
    ///
    /// Из шрифта, а не числом. Числом её однажды уже выписали в области
    /// ответа, и оно оказалось на две с половиной точки меньше настоящего:
    /// последняя строка обрезалась пополам.
    static var lineHeight: CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    /// Сколько строк поле показывает, прежде чем начать прокручиваться.
    static let maxLines = 5

    static var minHeight: CGFloat { lineHeight + 2 * inset.height }
    static var maxHeight: CGFloat { CGFloat(maxLines) * lineHeight + 2 * inset.height }

    /// Высота поля под этот текст.
    ///
    /// Считается настоящей вёрсткой строк (`boundingRect` с переносом),
    /// а не делением ширины на ширину: слова переносятся целиком, и грубая
    /// оценка расходится с рисунком тем сильнее, чем длиннее слова.
    static func height(for text: String, textWidth: CGFloat) -> CGFloat {
        guard textWidth > 0 else { return minHeight }

        // Пустая последняя строка в замер не попадает: `boundingRect`
        // считает по нарисованному, а после последнего перевода строки
        // не нарисовано ничего. Курсор при этом стоит именно там — и поле
        // не подрастало ровно в тот момент, когда человек нажал ⇧Enter.
        let measured = text.hasSuffix("\n") ? text + " " : text
        guard !measured.isEmpty else { return minHeight }

        let rect = (measured as NSString).boundingRect(
            with: CGSize(width: textWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return min(maxHeight, max(minHeight, ceil(rect.height) + 2 * inset.height))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let view = NSTextView()
        view.delegate = context.coordinator
        // Простой текст: чужое оформление вопросу ни к чему, а вставленный
        // чёрным по чёрному текст был бы не виден — той же бедой, которую
        // заметке лечили чисткой цветов.
        view.isRichText = false
        view.allowsUndo = true
        view.isEditable = true
        view.isSelectable = true
        view.font = Self.font
        view.textColor = .white
        view.drawsBackground = false
        // Курсор цветом панели: системная синева — единственное, чего
        // в вырезе нет нигде, и заводить её ради чёрточки незачем.
        view.insertionPointColor = NSColor(Palette.assistant)
        // Умные кавычки и тире выключены: сюда попадают адреса, куски кода
        // и чужой текст, и подмена символов в них — не помощь.
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false

        view.textContainerInset = Self.inset
        // Собственное поле контейнера в ноль: по умолчанию оно пять точек
        // и прибавляется к отступу, то есть текст начинается не там, где
        // сказано, — а по этому краю выравнивается подсказка пустого поля.
        view.textContainer?.lineFragmentPadding = 0

        view.minSize = CGSize(width: 0, height: 0)
        view.maxSize = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true

        view.string = text
        scroll.documentView = view

        // Фокус — сразу: панель открывают, чтобы печатать. Через очередь,
        // потому что до конца построения окна первым откликом назначать
        // некому.
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let view = scroll.documentView as? NSTextView else { return }
        // Текст снаружи подменяем только когда он и правда разошёлся:
        // отправка очищает поле, и без этого набранное осталось бы на экране.
        // На каждой перерисовке — нельзя: подмена сбивает курсор и отмену.
        if view.string != text {
            view.string = text
            // Текст, положенный снаружи, прокрутки за собой не тянет: она
            // следует за курсором, а курсор сам собой не двигается. Без
            // этого текст, переросший потолок, показывал бы своё начало,
            // а конец — тот, к которому сейчас припишут, — оставался
            // за краем поля.
            view.scrollRangeToVisible(view.selectedRange())
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextField

        init(_ parent: GrowingTextField) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }

        /// Enter — отправка, ⇧Enter — перевод строки.
        ///
        /// Через `doCommandBy`, а не разбором флагов в `keyDown`: систему
        /// об этом уже спросили за нас — она сама переводит нажатие
        /// в команду, и ⇧Enter приходит отдельным селектором
        /// `insertNewlineIgnoringFieldEditor`. Своя разборка флагов
        /// разошлась бы с ней на первой же нестандартной раскладке.
        ///
        /// `true` значит «нажатие обработано нами». Переводу строки
        /// отвечаем `false` — его вставит сам `NSTextView`, и делать это
        /// руками незачем.
        /// Тем же путём разбираются стрелки, Tab и Esc: они принадлежат
        /// списку команд под полем, а не тексту в нём. Каждый обработчик сам
        /// говорит, забрал ли он нажатие, — иначе поле съедало бы стрелки
        /// и там, где списка нет вовсе.
        func textView(
            _ textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.moveUp(_:)):
                return parent.onMoveHighlight?(-1) ?? false
            case #selector(NSResponder.moveDown(_:)):
                return parent.onMoveHighlight?(1) ?? false
            case #selector(NSResponder.moveLeft(_:)):
                return parent.onMoveAnswerAction?(-1) ?? false
            case #selector(NSResponder.moveRight(_:)):
                return parent.onMoveAnswerAction?(1) ?? false
            case #selector(NSResponder.insertTab(_:)):
                return parent.onCycleModel?() ?? false
            case #selector(NSResponder.cancelOperation(_:)):
                return parent.onEscape?() ?? false
            default:
                return false
            }
        }
    }
}
