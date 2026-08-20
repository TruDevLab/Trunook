import AppKit
import SwiftUI

/// Поле телесуфлера — `NSTextView` внутри прокрутки.
///
/// Не `TextEditor` из SwiftUI: тот работает с простой строкой и оформления
/// не знает вовсе, а здесь оформление — половина смысла. Через `NSTextView`
/// заодно достаются штатная отмена, распознавание ссылок и системная палитра
/// эмодзи — писать своё для каждого из них не пришлось.
struct TeleprompterTextView: NSViewRepresentable {
    @ObservedObject var store: TeleprompterStore

    func makeCoordinator() -> Coordinator { Coordinator(store: store) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let view = NSTextView()
        view.delegate = context.coordinator
        view.isRichText = true
        view.allowsUndo = true
        view.isEditable = true
        view.isSelectable = true
        // Распознавание ссылок на лету: адрес, набранный или вставленный
        // в текст, сам становится ссылкой — отдельно размечать его не нужно.
        view.isAutomaticLinkDetectionEnabled = true
        // Умные кавычки и тире выключены намеренно: в телесуфлер вставляют
        // готовую речь, и подмена символов в чужом тексте — не помощь.
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false

        view.drawsBackground = false
        view.textColor = .white
        view.insertionPointColor = NSColor(Palette.teleprompter)
        // Свой цвет ссылок: системный синий на чёрном читается как чужой,
        // а `.link` в тексте поле перекрашивает по-своему, что бы ни было
        // записано в самом атрибуте.
        view.linkTextAttributes = [
            .foregroundColor: NSColor(Palette.teleprompter),
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.iBeam,
        ]
        // Поля вокруг текста: строка, упирающаяся в кромку окна, читается
        // с трудом — а читать её будут вслух и на скорости.
        view.textContainerInset = CGSize(width: 14, height: 12)

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

        store.applyDefaultTyping(to: view)
        scroll.documentView = view
        store.attach(view)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Обновлять нечего: текст живёт в самом поле, и переписывать его
        // снаружи на каждой перерисовке значило бы сбивать курсор
        // и отмену. Вёрстка сюда только смотрит.
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let store: TeleprompterStore

        init(store: TeleprompterStore) {
            self.store = store
        }

        func textDidChange(_ notification: Notification) {
            store.textDidChange()
        }

        /// Ссылку в поле не открываем: телесуфлер правят, а не листают, и уход
        /// в браузер посреди репетиции — последнее, чего от него ждут.
        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            true
        }
    }
}
