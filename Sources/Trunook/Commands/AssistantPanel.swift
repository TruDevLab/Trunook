import SwiftUI
import AppKit

/// Ответ модели прямо в вырезе: пишется по мере поступления, снизу —
/// что с ним делать.
struct AssistantPanel: View {
    @ObservedObject var session: AssistantSession
    let metrics: NotchMetrics
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onCompose: () -> Void
    let onSend: (String) -> Void
    let onClose: () -> Void

    static var width: CGFloat { NotchStyle.scaled(480) }
    static let headerHeight: CGFloat = 24
    /// Высота нижней строки. Ровно по самому высокому в ней — полю ввода:
    /// лишний люфт уходил в нижнее поле панели, и снизу оказывалось
    /// на две точки больше, чем по бокам.
    static let footerHeight: CGFloat = 26
    /// Потолок области ответа: дальше она прокручивается.
    static let maxBodyHeight: CGFloat = 168
    static let lineHeight: CGFloat = 15

    /// Поле от чёрного тела панели — одинаковое слева, справа и снизу.
    /// Содержимое здесь тянется во всю ширину, поэтому вогнутое плечо формы
    /// приходится считать явно: см. `NotchStyle.shoulderInset`.
    static let bodyPadding: CGFloat = NotchStyle.bottomPadding
    /// Сколько всего занято полями по горизонтали: по этому числу меряется
    /// текст ответа, когда панель садится по содержимому.
    static var horizontalPadding: CGFloat { bodyPadding + NotchStyle.shoulderInset }

    /// Высота строки ввода — во всю высоту нижней строки, чтобы поле
    /// от неё не отставало.
    static var fieldHeight: CGFloat { footerHeight }

    static let answerFont = NSFont.systemFont(ofSize: 12)

    /// Высота области ответа.
    ///
    /// Пока идёт поток — во всю доступную: панель, подраставшая на каждой
    /// новой строке, дёргала бы вырез десяток раз за ответ, и читать текст
    /// в прыгающем окне невозможно. Когда поток закончился, панель садится
    /// по содержимому — одним движением, и короткий ответ не оставляет
    /// под собой пустое поле.
    static func bodyHeight(answer: String, isStreaming: Bool) -> CGFloat {
        guard !isStreaming else { return maxBodyHeight }
        guard !answer.isEmpty else { return lineHeight * 2 }

        // Замеряем текст без разметки: звёздочки и решётки на экран
        // не попадают, а ширину строки заметно меняют.
        let available = width - 2 * horizontalPadding
        let rows = MarkdownRender.plain(answer)
            .components(separatedBy: "\n")
            .reduce(0) { total, line in
                let measured = TextMeasure.width(line, font: answerFont)
                return total + max(1, Int(ceil(measured / available)))
            }
        return min(maxBodyHeight, max(lineHeight * 2, CGFloat(rows) * lineHeight))
    }

    static func height(notchHeight: CGFloat, answer: String = "", isStreaming: Bool = true) -> CGFloat {
        NotchStyle.height(
            notchHeight: notchHeight,
            contentHeight: bodyHeight(answer: answer, isStreaming: isStreaming)
                + NotchStyle.gridSpacing + footerHeight
        )
    }

    var body: some View {
        NotchPanel(metrics: metrics, width: Self.width, bodyPadding: Self.bodyPadding) {
            HStack(spacing: 6) {
                NotchPanelTitle(
                    symbol: "sparkles",
                    title: session.title.isEmpty ? t("Модель") : session.title,
                    tint: Palette.assistant
                )
                // Пока идёт поток — вертушка рядом с названием: она
                // и объясняет, почему панель пуста.
                if session.isStreaming {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.55)
                        .frame(width: 12, height: 12)
                }
            }
        } trailing: {
            NotchPanelButton(symbol: "xmark", hint: t("Закрыть"), action: onClose)
        } content: {
            VStack(alignment: .leading, spacing: NotchStyle.gridSpacing) {
                body_
                footer
            }
        }
    }

    /// Имя с подчёркиванием: `body` занято протоколом View.
    private var emptyText: String {
        if session.isStreaming { return t("Модель думает…") }
        return session.hasNoConversation ? t("Ответ появится здесь") : ""
    }

    private var body_: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 3) {
                    if let error = session.error {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: NotchStyle.font(11.5)))
                            .foregroundStyle(.orange)
                    }
                    if session.answer.isEmpty {
                        // Пустое место под ответом молчит непонятно: у панели,
                        // открытой кнопкой, ответа ещё нет и не было.
                        Text(emptyText)
                            .font(.system(size: NotchStyle.font(12)))
                            .foregroundStyle(.white.opacity(0.4))
                    } else {
                        ForEach(MarkdownRender.lines(from: session.answer)) { line in
                            markdownLine(line)
                        }
                    }
                    // Якорь для прокрутки: следим за хвостом, а не за всем
                    // текстом — иначе рывок на каждом слове.
                    Color.clear.frame(height: 1).id(Self.bottomAnchor)
                }
            }
            .frame(height: Self.bodyHeight(answer: session.answer, isStreaming: session.isStreaming))
            .onChange(of: session.answer) { _ in
                withAnimation(.linear(duration: 0.1)) {
                    proxy.scrollTo(Self.bottomAnchor, anchor: .bottom)
                }
            }
        }
    }

    private static let bottomAnchor = "assistant-bottom"

    /// Одна строка ответа. Отступы и маркеры расставлены здесь, выделение
    /// внутри строки уже разобрано.
    @ViewBuilder
    private func markdownLine(_ line: MarkdownRender.Line) -> some View {
        switch line.kind {
        case .rule:
            Divider().overlay(.white.opacity(0.15))

        case let .heading(level):
            Text(line.text)
                .font(.system(size: level == 1 ? 13.5 : 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 2)
                .frame(maxWidth: .infinity, alignment: .leading)

        case let .item(marker):
            // Маркер в колонке постоянной ширины, текст — своей: иначе
            // перенос длинного пункта уезжает под сам маркер и список
            // перестаёт читаться списком.
            HStack(alignment: .top, spacing: 6) {
                Text(marker)
                    .font(.system(size: NotchStyle.font(12)))
                    .foregroundStyle(.white.opacity(NotchStyle.tertiaryOpacity))
                    .frame(width: 14, alignment: .trailing)
                Text(line.text)
                    .font(.system(size: NotchStyle.font(12)))
                    .foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .quote:
            HStack(spacing: 8) {
                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 2)
                Text(line.text)
                    .font(.system(size: NotchStyle.font(12)))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 0)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .code:
            Text(line.text)
                .font(.system(size: NotchStyle.font(11), design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: NotchStyle.artRadius, style: .continuous).fill(.white.opacity(0.07)))

        case .paragraph where line.plain.isEmpty:
            // Пустая строка разделяет абзацы. Пустой `Text` занял бы целую
            // строку — здесь хватает узкого просвета.
            Color.clear.frame(height: 4)

        case .paragraph:
            Text(line.text)
                .font(.system(size: NotchStyle.font(12)))
                .foregroundStyle(.white.opacity(0.92))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if session.isComposing {
            HStack(spacing: 8) {
                FocusedTextField(
                    text: Binding(
                        get: { session.draft },
                        set: { session.draft = $0 }
                    ),
                    // Подсказка разная: первый вопрос задают с чистого листа,
                    // встречный — по уже сказанному.
                    placeholder: session.hasNoConversation
                        ? t("Спросите что угодно")
                        : t("Спросите ещё"),
                    onSubmit: { onSend(session.draft) },
                    onFocusChange: { session.isDraftFocused = $0 }
                )
                .frame(height: Self.fieldHeight)
                .padding(.horizontal, 12)
                // Подложка: без неё поле ввода на чёрном не отличалось
                // от области ответа, и было непонятно, куда писать.
                // Заливка светлая, как у плиток и круглых кнопок: прежняя
                // чёрная с прозрачностью на чёрном фоне не давала ничего,
                // и поле держалось на одной обводке.
                //
                // Скругление во всю высоту, а не углы в семь точек: вырез
                // и всё, что в нём, скруглено щедро, и почти прямой угол
                // рядом с круглой кнопкой «Отправить» читался как чужой.
                //
                // Капсула обычная, не `.continuous`: у сглаженной обводка
                // торца рвётся — дуга не доходит до края, и слева от неё
                // остаётся отдельный вертикальный огрызок.
                //
                // Обводка вдвое ярче и вдвое толще, когда поле в фокусе.
                // Это и есть кольцо фокуса — своей формы и своего цвета,
                // вместо системного синего прямоугольника, который ложился
                // поперёк капсулы.
                .background(
                    Capsule()
                        .fill(.white.opacity(NotchStyle.tileFill))
                        .overlay(
                            Capsule().strokeBorder(
                                session.isDraftFocused
                                    ? Palette.assistant.opacity(NotchStyle.dense(0.85))
                                    : .white.opacity(NotchStyle.dense(0.12)),
                                lineWidth: session.isDraftFocused ? 1.5 : 1
                            )
                        )
                )
                .animation(.easeOut(duration: 0.12), value: session.isDraftFocused)

                action(t("Отправить"), symbol: "arrow.up.circle.fill") { onSend(session.draft) }
                    .disabled(session.draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .frame(height: Self.footerHeight)
        } else {
            HStack(spacing: 8) {
                action(t("Ответить"), symbol: "arrowshape.turn.up.left") { onCompose() }
                Spacer(minLength: 0)
                action(t("Скопировать"), symbol: "doc.on.doc") { onCopy() }
                action(t("Вставить"), symbol: "text.insert") { onPaste() }
            }
            .frame(height: Self.footerHeight)
            // Пока ответа нет, действовать не с чем.
            .disabled(session.answer.isEmpty)
            .opacity(session.answer.isEmpty ? 0.4 : 1)
        }
    }

    private func action(_ title: String, symbol: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol)
                .font(.system(size: NotchStyle.font(11), weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Capsule().fill(.white.opacity(0.16)))
        }
        .buttonStyle(PressableStyle())
        .fixedSize()
    }
}

/// Поле ввода, которое само забирает фокус при появлении.
///
/// На AppKit, а не `TextField` со `@FocusState`: панель — окно-агент,
/// первый отклик ей нужно назначать вручную, и делать это надёжнее там,
/// где видно само `NSView`.
struct FocusedTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    /// Поле получило или отдало первый отклик. Обводку по этому признаку
    /// рисует подложка — своей формы и своего цвета.
    var onFocusChange: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    /// Подсказка своим цветом: системный на тёмном фоне почти чёрный
    /// и не читается — поле выглядело пустым и без объяснений.
    private static func hint(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .foregroundColor: NSColor.white.withAlphaComponent(0.4),
            .font: NSFont.systemFont(ofSize: 12),
        ])
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusReportingField()
        field.onFocusChange = onFocusChange
        field.delegate = context.coordinator
        field.placeholderAttributedString = Self.hint(placeholder)
        field.font = .systemFont(ofSize: 12)
        field.textColor = .white
        // Фон и рамку рисует подложка SwiftUI. Своя заливка здесь была
        // прямоугольной и торчала бы углами из скруглённой подложки.
        field.drawsBackground = false
        field.isBordered = false
        // Системное кольцо снято, но признак фокуса остался — его рисует
        // сама подложка в `AssistantPanel`.
        //
        // Кольцо тут побывало дважды. Сначала его сняли, и при полном доступе
        // с клавиатуры поле не показывало, что оно в фокусе. Потом вернули
        // как `.exterior` — и получили синий системный прямоугольник поверх
        // капсулы: чужой формы, чужого цвета и в единственном месте
        // приложения, где вообще есть системная синева.
        //
        // Верно и то и другое: признак нужен, но рисовать его должно то же,
        // что рисует само поле. Поле сообщает о фокусе наружу, подложка
        // меняет обводку — форма своя, цвет свой.
        field.focusRingType = .none
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.placeholderAttributedString = Self.hint(placeholder)
    }

    /// `NSTextField`, сообщающий о своём фокусе.
    ///
    /// Через подкласс, а не через делегат: `controlTextDidBeginEditing`
    /// приходит на первом набранном символе, а обводка нужна с того
    /// мгновения, как поле стало первым откликом, — то есть до набора.
    ///
    /// Редактирование в `NSTextField` ведёт общий на окно `NSTextView`,
    /// поэтому первым откликом становится он, а поле остаётся его
    /// «делегатом поля». Отсюда проверка на `currentEditor`, а не просто
    /// возврат `true`.
    final class FocusReportingField: NSTextField {
        var onFocusChange: (Bool) -> Void = { _ in }

        override func becomeFirstResponder() -> Bool {
            let became = super.becomeFirstResponder()
            guard became else { return false }
            // Курсор цветом панели, а не системным синим. Синева ушла
            // с обводки, но осталась бы в мигающей чёрточке — в единственном
            // месте выреза, где вообще есть системный акцент.
            //
            // Здесь, а не в `makeNSView`: у `NSTextField` своего курсора нет,
            // рисует его общий на окно редактор полей, и достаётся он только
            // тогда, когда поле уже стало первым откликом.
            (currentEditor() as? NSTextView)?.insertionPointColor =
                NSColor(Palette.assistant)
            onFocusChange(true)
            return true
        }

        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned { onFocusChange(false) }
            return resigned
        }

        override func textDidEndEditing(_ notification: Notification) {
            super.textDidEndEditing(notification)
            onFocusChange(false)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FocusedTextField

        init(_ parent: FocusedTextField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.onSubmit()
            return true
        }
    }
}
