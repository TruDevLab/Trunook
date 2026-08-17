import SwiftUI

/// Кто из плиток сейчас под курсором.
///
/// Общий на всё приложение, а не по одному на панель: вырез один, и плитка
/// под курсором в нём тоже одна. Отдельный объект нужен потому, что `@State`
/// в этом тулчейне недоступен — держать признак наведения внутри самой
/// плитки нечем.
final class HoverTracker: ObservableObject {
    static let shared = HoverTracker()

    @Published private(set) var hovered: String?

    func set(_ id: String, isInside: Bool) {
        if isInside {
            hovered = id
        } else if hovered == id {
            // Только своё: курсор уже мог перейти на соседнюю плитку,
            // и та успела записаться раньше, чем эта сообщила об уходе.
            hovered = nil
        }
    }

    func isHovered(_ id: String) -> Bool { hovered == id }
}

/// Плитка панели: общая подложка, скругление и отклик на курсор.
///
/// До неё панели никак не отзывались на наведение — курсор ходил по мёртвому
/// полю, и понять, попадёшь ли ты в плитку, можно было только нажав.
struct NotchTile<Content: View>: View {
    let id: String
    var radius: CGFloat = NotchStyle.tileRadius
    var isEnabled = true
    @ViewBuilder var content: () -> Content

    @ObservedObject private var hover = HoverTracker.shared

    private var isLit: Bool { isEnabled && hover.isHovered(id) }

    var body: some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(.white.opacity(isLit ? NotchStyle.tileFillHover : NotchStyle.tileFill))
            )
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onHover { inside in hover.set(id, isInside: inside) }
            .animation(.easeOut(duration: 0.12), value: isLit)
    }
}
