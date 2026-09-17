import TrunookXPC
import AppKit
import ApplicationServices

/// Куда вставлять в чужом приложении.
///
/// Вставка — это ⌘V, посланное активному приложению, и попадает оно туда,
/// где у приложения стоит фокус. Пока текст захватывали из поля ввода, всё
/// сходилось само: фокус там и оставался. А стоило скопировать из места,
/// где ввода нет, — из ответа в чате, из статьи, из списка, — и нажатие
/// уходило в никуда: приложение получало ⌘V, а вставлять было некуда.
/// Снаружи это выглядело как «кнопка не работает».
///
/// Поэтому перед нажатием фокус ставится в поле ввода — тем же приёмом,
/// каким нажимаются кнопки веб-встречи: `AXFocused` на элемент чужого
/// дерева. Это единственное, что работает и в обычных окнах, и в вебе.
enum PasteTarget {
    /// Роли, в которые можно писать.
    ///
    /// Не только по ролям: веб-поля сплошь и рядом зовутся `AXTextArea`,
    /// но встречается и голый `AXGroup` с редактируемым значением. Роль —
    /// быстрая проверка, настоящая — «значение можно записать».
    private static let editableRoles: Set<String> = [
        kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole,
    ]

    /// Подготовить приложение к вставке. Возвращает, есть ли куда вставлять.
    ///
    /// Зовётся **не с главного потока**: каждый шаг обхода — обращение
    /// к чужому процессу, и на тяжёлой странице их тысячи. Обход с главного
    /// потока однажды уже вешал запуск приложения насмерть.
    static func prepare(pid: pid_t) -> Bool {
        guard AXTree.isTrusted else { return false }
        let app = AXTree.application(pid: pid)

        // Фокус уже в поле — не трогаем ничего. Человек мог выделить в нём
        // кусок, чтобы заменить его вставкой, и увод фокуса это выделение
        // потерял бы.
        if let focused = focusedElement(of: app), isEditable(focused) { return true }

        guard let window = focusedWindow(of: app) else { return false }
        let fields = editableFields(in: window, bounds: AXTree.frame(of: window))
        guard let field = best(of: fields) else {
            DebugLog.write("вставка: поля ввода в окне не нашлось")
            return false
        }
        let done = AXUIElementSetAttributeValue(
            field.element, kAXFocusedAttribute as CFString, kCFBooleanTrue
        ) == .success
        DebugLog.write(
            "вставка: фокус в поле \(field.role) \(Int(field.frame.width))×\(Int(field.frame.height))"
                + (done ? "" : " — не принял")
        )
        return done
    }

    /// Что нашлось бы, не трогая фокус, — под отладку.
    ///
    /// Нажать «Вставить» из сессии нечем, а знать, куда попадёт вставка,
    /// надо: проба говорит это словами, ничего не меняя в чужом окне.
    static func probe(pid: pid_t) -> String {
        guard AXTree.isTrusted else { return "нет Универсального доступа" }
        let app = AXTree.application(pid: pid)
        let focused = focusedElement(of: app)
        let focusedRole = focused.map { AXTree.role(of: $0) } ?? "нет"
        let focusedFits = focused.map { isEditable($0) } ?? false
        guard !focusedFits else { return "фокус уже в поле (\(focusedRole)) — вставка попадёт туда" }

        guard let window = focusedWindow(of: app) else {
            return "фокус на \(focusedRole), окна не видно"
        }
        let fields = editableFields(in: window, bounds: AXTree.frame(of: window))
        guard let field = best(of: fields) else {
            return "фокус на \(focusedRole), полей ввода не нашлось"
        }
        return "фокус на \(focusedRole); из \(fields.count) полей возьмём"
            + " \(field.role) \(Int(field.frame.width))×\(Int(field.frame.height))"
            + " внизу на \(Int(field.frame.minY))"
    }

    // MARK: - Выбор поля

    struct Field {
        let element: AXUIElement
        let role: String
        let frame: CGRect
    }

    /// Наименьшее поле, которое вообще считается полем.
    ///
    /// Поймано на браузере: среди восьмидесяти девяти «полей» страницы
    /// выбралось `AXGroup` размером 10×8 за верхним краем окна. Настоящее
    /// поле ввода такого размера не бывает, а невидимых заготовок
    /// на странице сколько угодно.
    static let minimumSize = CGSize(width: 60, height: 14)

    /// Какое из полей взять.
    ///
    /// Три признака по старшинству:
    ///
    /// 1. **Настоящая роль важнее.** `AXTextArea` и `AXTextField` — это поля
    ///    по объявлению самого приложения, а `AXGroup` с записываемым
    ///    значением — догадка: в вебе так выглядит и поле ввода,
    ///    и невидимая заготовка.
    /// 2. **Ниже — важнее.** В чате, письме и заметке поле ввода стоит
    ///    внизу, а всё, что выше, — поиск, заголовок и боковые списки.
    ///    Попасть в поиск вместо строки сообщения хуже, чем не вставить.
    /// 3. **Крупнее — важнее.** Равные по низу разводит площадь: у поля
    ///    ввода она больше, чем у однострочного поля рядом с ним.
    static func best<Candidate>(
        of fields: [Candidate],
        frame: (Candidate) -> CGRect,
        isNamedField: (Candidate) -> Bool = { _ in true }
    ) -> Candidate? {
        fields.max { left, right in
            if isNamedField(left) != isNamedField(right) { return !isNamedField(left) }
            let a = frame(left)
            let b = frame(right)
            if a.minY != b.minY { return a.minY < b.minY }
            return a.width * a.height < b.width * b.height
        }
    }

    static func best(of fields: [Field]) -> Field? {
        best(of: fields, frame: { $0.frame }, isNamedField: { editableRoles.contains($0.role) })
    }

    // MARK: - Обход

    private static func focusedElement(of app: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app, kAXFocusedUIElementAttribute as CFString, &value
        ) == .success else { return nil }
        return AXTree.element(value)
    }

    private static func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            app, kAXFocusedWindowAttribute as CFString, &value
        ) == .success, let window = AXTree.element(value) {
            return window
        }
        return AXTree.windows(of: app).first
    }

    /// Можно ли записать в элемент значение.
    ///
    /// Спрашиваем само приложение, а не гадаем по роли: `AXTextArea`
    /// встречается и у текста, который только читают, — у ответа в чате,
    /// например, — а редактируемое поле в вебе бывает и `AXGroup`.
    private static func isEditable(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(
            element, kAXValueAttribute as CFString, &settable
        ) == .success else { return false }
        guard settable.boolValue else { return false }
        return AXTree.isEnabled(element)
    }

    /// Поля ввода в окне. Обход с тем же потолком узлов, что и у встреч:
    /// у веб-страницы их тысячи, и «долго» здесь означает минуты.
    ///
    /// `bounds` — рамка самого окна. Всё, что лежит за ней, отбрасывается:
    /// страница держит невидимые заготовки полей далеко за краем, и одна
    /// такая — 10×8 над верхней кромкой — однажды и выбралась.
    private static func editableFields(in window: AXUIElement, bounds: CGRect?) -> [Field] {
        var found: [Field] = []
        var queue = [window]
        var visited = 0

        while !queue.isEmpty, visited < AXTree.nodeBudget {
            let element = queue.removeFirst()
            visited += 1

            if let frame = AXTree.frame(of: element), fits(frame, in: bounds),
               isEditable(element) {
                found.append(Field(element: element, role: AXTree.role(of: element), frame: frame))
            }
            queue.append(contentsOf: AXTree.children(of: element))
        }
        return found
    }

    /// Поле видно и стоит в окне.
    static func fits(_ frame: CGRect, in bounds: CGRect?) -> Bool {
        guard frame.width >= minimumSize.width, frame.height >= minimumSize.height else {
            return false
        }
        guard let bounds, bounds.width > 1, bounds.height > 1 else { return true }
        return bounds.intersects(frame)
    }
}
