import AppKit

/// Главное меню приложения — невидимое, но обязательное.
///
/// Trunook работает как `LSUIElement`: полосы меню у него нет и быть не должно.
/// Из-за этого казалось, что главное меню ему не нужно вовсе, и его не было.
///
/// Но в macOS сочетания правки текста раздаёт именно меню: ⌘C, ⌘V, ⌘X, ⌘A и ⌘Z
/// доставляются через `performKeyEquivalent` по пунктам «Правки». Без меню
/// в полях ввода не работало ничего — ни копирование промта в настройках,
/// ни вставка в поле встречного вопроса к модели.
///
/// Меню при этом остаётся невидимым: сочетания оно раздаёт и так, а полосу
/// меню приложение-агент не показывает.
///
/// Действия отправляются с пустой целью — по цепочке отклика. Так их
/// подхватывает то поле ввода, которое сейчас в фокусе, каким бы окном
/// оно ни было.
enum AppMenu {
    static func install() {
        let main = NSMenu()

        // Пункт приложения обязателен: без него система считает меню
        // неполным и не отдаёт ему сочетания.
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: tf("Завершить %@", AppInfo.name),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        editItem.submenu = editMenu()
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: t("Правка"))
        let items: [(String, Selector, String, NSEvent.ModifierFlags)] = [
            (t("Отменить"), Selector(("undo:")), "z", .command),
            (t("Повторить"), Selector(("redo:")), "z", [.command, .shift]),
        ]
        for (title, action, key, modifiers) in items {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let editing: [(String, Selector, String)] = [
            (t("Вырезать"), #selector(NSText.cut(_:)), "x"),
            (t("Скопировать"), #selector(NSText.copy(_:)), "c"),
            (t("Вставить"), #selector(NSText.paste(_:)), "v"),
            (t("Выбрать всё"), #selector(NSText.selectAll(_:)), "a"),
        ]
        for (title, action, key) in editing {
            menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        return menu
    }
}
