import SwiftUI

/// Чашка кофе в левом крыле раскрытой панели: не давать экрану гаснуть.
///
/// Рядом с погодой, а не среди кнопок справа, и это не про симметрию. Справа
/// живут действия — «спросить модель», «настройки», — которые что-то открывают
/// и заканчиваются. Чашка не действие, а состояние, и стоять ей рядом
/// со сведениями о мире, где стоит погода.
///
/// Включённость показана **подложкой**, а не сменой значка. Значок в двадцать
/// точек человек не сличает по памяти — залитая чашка от пустой отличается
/// не сразу, — а появившийся под ней прямоугольник виден боковым зрением.
struct CaffeineButton: View {
    let isOn: Bool
    let action: () -> Void

    private static let side: CGFloat = 20

    var body: some View {
        Button(action: action) {
            // Значок один и тот же в обоих состояниях: контурная чашка
            // в одиннадцать пунктов от залитой почти неотличима, а разницу
            // и должна показывать подложка, а не подмена глифа.
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isOn ? Palette.caffeine : .white.opacity(NotchStyle.secondaryOpacity))
                .frame(width: Self.side, height: Self.side)
                .background(shape.fill(isOn ? Palette.caffeine.opacity(0.2) : .clear))
                // Без этого нажимается только сама чашка: подложка нарисована
                // фоном, а метка кнопки о ней не знает и остаётся прозрачной
                // для попаданий.
                .contentShape(shape)
        }
        .buttonStyle(PressableStyle())
        .help(isOn ? t("Экран не гаснет — нажмите, чтобы вернуть как было")
                   : t("Не давать экрану гаснуть и блокироваться"))
        .accessibilityLabel(t("Не давать экрану гаснуть и блокироваться"))
        .animation(.easeOut(duration: 0.15), value: isOn)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: NotchStyle.rowRadius, style: .continuous)
    }
}
