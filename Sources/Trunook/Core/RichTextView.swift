import AppKit
import SwiftUI

/// Поле оформленного текста — `NSTextView` внутри прокрутки.
///
/// Не `TextEditor` из SwiftUI: тот работает с простой строкой и оформления
/// не знает вовсе, а здесь оформление — половина смысла. Через `NSTextView`
/// заодно достаются штатная отмена, распознавание ссылок и системная палитра
/// эмодзи — писать своё для каждого из них не пришлось.
///
/// Вынесено из телесуфлера, когда такое же поле понадобилось панели модели.
/// Отличаются они кеглем, цветом и полями — это параметры; всё остальное
/// у них общее.
struct RichTextView: NSViewRepresentable {
    let editor: RichTextEditor
    /// Поле вокруг текста. Наружу — потому что по нему выравнивается
    /// подсказка пустого поля: два числа порознь разъехались бы.
    var inset: CGSize
    /// Текст изменился рукой человека.
    var onChange: () -> Void
    /// Что делать по нажатию на ссылку в самом поле.
    ///
    /// По умолчанию ничего: и телесуфлер, и заметку **правят**, а не листают,
    /// и уход в браузер посреди правки — последнее, чего от поля ждут.
    var opensLinks = false
    /// В поле что-то вставили — из буфера или перетаскиванием.
    ///
    /// Наружу, а не внутрь редактора: чистка чужого оформления — решение
    /// того, чьё это поле, и телесуфлеру с заметкой оно может понадобиться
    /// разное.
    var onPaste: (() -> Void)?
    /// Поле построено и отдано редактору.
    ///
    /// Нужно тому, кто кладёт в поле готовый текст — сохранённую речь или
    /// заметку, открытую на правку. Зовётся здесь, а не из `onAppear`:
    /// к появлению вида поле уже должно быть заполнено, иначе первый кадр
    /// показывает пустоту, а следом текст возникает рывком.
    var onAttach: ((NSTextView) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange, opensLinks: opensLinks)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let view = PastingTextView()
        view.onPaste = onPaste
        view.delegate = context.coordinator
        view.isRichText = true
        view.allowsUndo = true
        view.isEditable = true
        view.isSelectable = true
        // Распознавание ссылок на лету: адрес, набранный или вставленный
        // в текст, сам становится ссылкой — отдельно размечать его не нужно.
        view.isAutomaticLinkDetectionEnabled = true
        // Умные кавычки и тире выключены намеренно: сюда вставляют готовый
        // чужой текст, и подмена символов в нём — не помощь.
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false

        view.drawsBackground = false
        view.textColor = .white
        view.insertionPointColor = editor.style.tint
        // Свой цвет ссылок: системный синий на чёрном читается как чужой,
        // а `.link` в тексте поле перекрашивает по-своему, что бы ни было
        // записано в самом атрибуте.
        view.linkTextAttributes = [
            .foregroundColor: editor.style.tint,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.iBeam,
        ]
        // Поля вокруг текста: строка, упирающаяся в кромку окна, читается
        // с трудом.
        view.textContainerInset = inset
        // Собственное поле контейнера — в ноль. По умолчанию оно пять точек
        // и прибавляется к отступу слева, то есть текст начинается не там,
        // где сказано. Подсказка пустого поля рисуется поверх средствами
        // SwiftUI и об эти пять точек и споткнулась: курсор вставал
        // на первой букве подсказки, а не перед ней.
        //
        // Ноль, а не прибавка к подсказке: отступ должен значить ровно то,
        // что в нём написано, иначе следующий, кто станет что-нибудь
        // выравнивать по краю текста, споткнётся так же.
        view.textContainer?.lineFragmentPadding = 0

        // Ширина по окну, высота по тексту: так работает прокрутка.
        view.minSize = CGSize(width: 0, height: 0)
        view.maxSize = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = CGSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )

        editor.applyDefaultTyping(to: view)
        scroll.documentView = view
        editor.attach(view)
        onAttach?(view)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Текст снаружи не переписываем: он живёт в самом поле, и подмена
        // его на каждой перерисовке сбивала бы курсор и отмену. Вёрстка сюда
        // только смотрит. Обновляем лишь замыкание — оно у нового значения
        // структуры своё.
        context.coordinator.onChange = onChange
        (nsView.documentView as? PastingTextView)?.onPaste = onPaste
    }

    /// `NSTextView`, сообщающий о вставке.
    ///
    /// Через подкласс, а не через делегата: у `NSTextViewDelegate` нет метода
    /// «вставили», а `textDidChange` не отличает вставку от набора руками —
    /// перебирать же всё содержимое на каждой нажатой клавише ради чужих
    /// цветов расточительно.
    ///
    /// Перекрыты три пути: обычная вставка, вставка без оформления
    /// и `readSelection` — им приходит перетаскивание. Первый из них зовёт
    /// третий внутри себя, так что сообщение иногда приходит дважды; чистка
    /// от этого не портится — она идемпотентна.
    final class PastingTextView: NSTextView {
        var onPaste: (() -> Void)?

        override func paste(_ sender: Any?) {
            super.paste(sender)
            onPaste?()
        }

        override func pasteAsPlainText(_ sender: Any?) {
            super.pasteAsPlainText(sender)
            onPaste?()
        }

        override func readSelection(
            from pboard: NSPasteboard,
            type: NSPasteboard.PasteboardType
        ) -> Bool {
            let accepted = super.readSelection(from: pboard, type: type)
            if accepted { onPaste?() }
            return accepted
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onChange: () -> Void
        private let opensLinks: Bool

        init(onChange: @escaping () -> Void, opensLinks: Bool) {
            self.onChange = onChange
            self.opensLinks = opensLinks
        }

        func textDidChange(_ notification: Notification) {
            onChange()
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            // `true` значит «нажатие обработано нами», то есть система
            // ссылку не откроет.
            !opensLinks
        }
    }
}
