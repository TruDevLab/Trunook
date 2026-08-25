import AppKit
import SwiftUI

/// Поле телесуфлера.
///
/// Само поле — общее с панелью модели (`RichTextView`); здесь остаётся то,
/// что у телесуфлера своё: отступ вокруг текста и то, что сохранённая речь
/// кладётся в поле сразу, как оно построено.
///
/// Тип не убран в пользу прямого вызова `RichTextView` нарочно: по `textInset`
/// выравнивается подсказка пустого суфлера в `TeleprompterPanel`, и эти два
/// числа обязаны браться из одного места. Порознь они уже разъезжались —
/// подсказка стояла на пять точек левее текста и была вдвое мельче.
struct TeleprompterTextView: View {
    /// Поле вокруг текста. Строка, упирающаяся в кромку окна, читается
    /// с трудом — а читать её будут вслух и на скорости.
    static let textInset = CGSize(width: 14, height: 12)

    @ObservedObject var store: TeleprompterStore

    var body: some View {
        RichTextView(
            editor: store.editor,
            inset: Self.textInset,
            onChange: store.textDidChange,
            onPaste: store.didPaste,
            onAttach: store.attach
        )
    }
}
