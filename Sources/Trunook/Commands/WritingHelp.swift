import TrunookXPC
import AppKit
import SwiftUI

/// Что предложить к выделенному тексту: сам текст и кнопки команд.
///
/// Кнопки — снимком названия и значка, а не командами целиком: плашка
/// только рисует, а запускать будет контроллер по номеру, взяв команду
/// из настроек. Так правка команды в настройках не разойдётся с плашкой,
/// висящей в этот миг.
struct WritingHelpOffer: Equatable {
    struct Button: Equatable, Identifiable {
        let id: Int
        let title: String
        let symbol: String
    }

    let text: String
    let buttons: [Button]
}

/// Помощь при письме: выделили текст в любом приложении — под чёлкой плашка
/// с кнопками команд. Чистые правила, под тестом.
enum WritingHelpRules {
    /// Больше шести кнопок плашка не держит: шире она уже спорит с текстом.
    static let limit = 6

    /// Первые шесть команд, которые работают с выделенным: запросы к модели,
    /// запись в заметки и команды из «Команд», которым передаётся текст.
    /// Открыть приложение или ссылку к выделенному отношения не имеет.
    /// Команды к модели с выключенной моделью не показываются — ответили бы
    /// отказом.
    static func commands(from commands: [QuickCommand], modelEnabled: Bool) -> [QuickCommand] {
        let usable = commands.filter { command in
            guard command.isConfigured else { return false }
            switch command.kind {
            case .ollama: return modelEnabled
            case .saveToNotes: return true
            case .shortcut: return command.passesSelection
            case .openApp, .openPath, .openURL, .appleScript: return false
            }
        }
        return Array(usable.prefix(limit))
    }

    /// Стоит ли предлагать помощь к такому выделению.
    ///
    /// Одна буква или знак — это щелчок с потягиванием, а не выделенный
    /// текст. Слишком длинное — выделили всё подряд (⌘A в документе), и плашка
    /// над этим скорее мешает: команду к такому тексту зовут ⌃⌥C.
    static func offers(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 2 && trimmed.count <= 20_000
            && trimmed.contains(where: { $0.isLetter })
    }

    static func offer(text: String, commands: [QuickCommand]) -> WritingHelpOffer {
        WritingHelpOffer(
            text: text,
            buttons: commands.map { .init(id: $0.id, title: $0.title, symbol: $0.effectiveSymbol) }
        )
    }
}

/// Куда уходят нажатия по плашке помощи.
///
/// Общим объектом, как у сердечка трека: плашка рисуется глубоко в вырезе,
/// и тянуть до неё ещё одно замыкание через весь `NotchView` ради шести
/// кнопок незачем. Обработчики ставит контроллер.
final class WritingHelp {
    static let shared = WritingHelp()

    /// Нажали кнопку команды — её номер.
    var onRun: ((Int) -> Void)?
    /// Нажали саму плашку — открыть панель команд с выделенным.
    var onOpen: (() -> Void)?

    func run(_ id: Int) { onRun?(id) }
    func open() { onOpen?() }
}

/// Следит, не выделили ли текст в чужом приложении.
///
/// Система о выделении не сообщает, а опрашивать фокус по таймеру — значит
/// дёргать чужое приложение несколько раз в секунду. Выделение же появляется
/// всегда по делу: протянули мышью, щёлкнули дважды или трижды, щёлкнули
/// с ⇧, выделили стрелками с ⇧ или нажали ⌘A. Только тогда и спрашиваем —
/// через дерево доступности, без ⌘C.
///
/// **Простой щелчок выделения не спрашивает** (энергоаудит 18 октября):
/// прежде вопрос чужому приложению уходил на каждое отпускание мыши и на каждую
/// заглавную букву (отпускание ⇧). Щелчок без протяжки выделение не создаёт,
/// а снимает — о нём сообщается как о пустом выделении, без вопроса.
///
/// Глобальные мониторы видят только события в чужих приложениях: щелчок
/// по самой плашке сюда не попадает и выделение заново не спрашивает.
final class SelectionWatcher {
    /// Выделение после отпускания: текст или `nil` — ничего не выделено.
    var onChange: ((String?) -> Void)?
    /// Включена ли помощь. Выключена — чужое приложение не спрашиваем вовсе.
    var isEnabled: () -> Bool = { true }

    private var monitors: [Any] = []
    private var pending: DispatchWorkItem?
    /// Где нажали кнопку — чтобы отличить протяжку от щелчка.
    private var pressedAt: CGPoint?

    /// Клавиши, которыми с ⇧ выделяют: стрелки, Home, End, страницы.
    static let selectionKeys: Set<UInt16> = [123, 124, 125, 126, 115, 119, 116, 121]

    /// Создаёт ли это отпускание мыши выделение. Чистое правило, под тестом.
    static func mouseSelects(clickCount: Int, shift: Bool, dragged: CGFloat) -> Bool {
        clickCount >= 2 || shift || dragged >= 4
    }

    /// Создаёт ли это отпускание клавиши выделение: ⇧ со стрелкой (и прочими
    /// клавишами хода) или ⌘A. Заглавная буква — нет.
    static func keySelects(keyCode: UInt16, shift: Bool, command: Bool) -> Bool {
        (shift && selectionKeys.contains(keyCode)) || (command && keyCode == 0)
    }

    func start() {
        guard monitors.isEmpty else { return }
        if let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            self?.pressedAt = NSEvent.mouseLocation
        }) {
            monitors.append(down)
        }
        if let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] event in
            guard let self, self.isEnabled() else { return }
            let now = NSEvent.mouseLocation
            let dragged = self.pressedAt.map { hypot(now.x - $0.x, now.y - $0.y) } ?? 0
            self.pressedAt = nil
            if Self.mouseSelects(clickCount: event.clickCount, shift: event.modifierFlags.contains(.shift),
                                 dragged: dragged) {
                self.schedule()
            } else {
                self.pending?.cancel()
                self.onChange?(nil)
            }
        }) {
            monitors.append(up)
        }
        if let keys = NSEvent.addGlobalMonitorForEvents(matching: .keyUp, handler: { [weak self] event in
            guard let self, self.isEnabled() else { return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if Self.keySelects(keyCode: event.keyCode, shift: flags.contains(.shift), command: flags.contains(.command)) {
                self.schedule()
            }
        }) {
            monitors.append(keys)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        pending?.cancel()
        pending = nil
    }

    /// Спросить чуть погодя: приложение обновляет выделение не в тот же миг,
    /// что отпускание, а двойной щелчок присылает два отпускания подряд.
    private func schedule() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.check() }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func check() {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier
                != ProcessInfo.processInfo.processIdentifier else { return }
        onChange?(SelectionReader.accessibilityText(timeout: 0.2))
    }
}

/// Кнопки команд на плашке помощи при письме — круглые, как кнопки ответа;
/// название всплывает под чёлкой при наведении.
struct WritingHelpButtons: View {
    let offer: WritingHelpOffer

    var body: some View {
        HStack(spacing: ActivityView.answerSpacing) {
            ForEach(offer.buttons) { button in
                Button { WritingHelp.shared.run(button.id) } label: {
                    Image(systemName: button.symbol)
                        .font(.system(size: NotchStyle.font(11), weight: .semibold))
                        .foregroundStyle(.white.opacity(NotchStyle.primaryOpacity))
                        .frame(width: ActivityView.answerDiameter, height: ActivityView.answerDiameter)
                        .background(Circle().fill(.white.opacity(0.14)))
                }
                .buttonStyle(NotchButtonStyle(diameter: ActivityView.answerDiameter))
                .notchHint(button.title)
                .accessibilityLabel(button.title)
            }
        }
        .fixedSize()
    }

    /// Между строкой текста и рядом кнопок.
    static let rowGap: CGFloat = 8

    /// Ширина ряда кнопок.
    static func rowWidth(for offer: WritingHelpOffer) -> CGFloat {
        let count = CGFloat(offer.buttons.count)
        guard count > 0 else { return 0 }
        return count * ActivityView.answerDiameter + (count - 1) * ActivityView.answerSpacing
    }

    /// Размеры плашки в два ряда. Ширина — по более широкому из рядов:
    /// кнопки помещаются всегда, текст — до обычного потолка плашки, дальше
    /// бежит строкой. Не уже свёрнутой формы с выступом — иначе плашка
    /// читалась бы обрубком под чёлкой.
    static func layout(for offer: WritingHelpOffer, text: String, metrics: NotchMetrics) -> ActivityLayout {
        let padding = 2 * ActivityLayout.leadingPadding
        let lead = ActivityLayout.iconSize + ActivityLayout.spacing
        let natural = padding + max(rowWidth(for: offer), lead + TextMeasure.width(text, font: ActivityLayout.textFont))
        let floor = max(metrics.closed.width + ActivityLayout.overhangBeyondNotch, padding + rowWidth(for: offer))
        let width = max(floor, min(ActivityLayout.maxWidth, natural))
        return ActivityLayout(panelWidth: width, textWidth: width - padding - lead)
    }

    /// На сколько плашка выше обычной: ряд кнопок с промежутком.
    static var extraHeight: CGFloat { rowGap + ActivityView.answerDiameter }
}
