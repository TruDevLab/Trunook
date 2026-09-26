import TrunookXPC
import AppKit
import Combine
import EventKit

/// Состояние окна знакомства: текущий шаг и живое состояние доступов.
///
/// Отдельный объект, а не `@State`: в этом тулчейне `@State` недоступен —
/// он реализован макросом, а плагин SwiftUI-макросов поставляется с Xcode.
final class WelcomeModel: ObservableObject {
    /// Шаги по порядку. Не все видны каждому: настройка календаря,
    /// погоды и помощника показывается, только если человек отметил их
    /// на шаге «Чем пользуетесь» (`WelcomeFlow.steps`).
    enum Step: Int, CaseIterable, Identifiable {
        case intro, features, uses, look, calendar, weather, ai, home, controls, permissions, done

        var id: Int { rawValue }

        /// Шаг что-то настраивает. У таких «Пропустить» ведёт к следующему
        /// шагу, а не закрывает знакомство: пропускают настройку, а не всё.
        var isSetup: Bool {
            switch self {
            case .uses, .look, .calendar, .weather, .ai, .home, .permissions: return true
            case .intro, .features, .controls, .done: return false
            }
        }

        /// Надпись над заголовком — она же метка шага в индикаторе.
        var eyebrow: String {
            switch self {
            case .intro: return t("ЗНАКОМСТВО")
            case .features: return t("ВОЗМОЖНОСТИ")
            case .uses: return t("ВАШ НАБОР")
            case .look: return t("ВИД")
            case .calendar: return t("КАЛЕНДАРЬ")
            case .weather: return t("ПОГОДА И ПЕРЕРЫВЫ")
            case .ai: return t("ПОМОЩНИК")
            case .home: return t("ГЛАВНЫЙ ЭКРАН")
            case .controls: return t("УПРАВЛЕНИЕ")
            case .permissions: return t("ДОСТУПЫ")
            case .done: return t("ГОТОВО")
            }
        }

        /// То же имя обычным регистром — для диктора.
        ///
        /// Не `eyebrow`: тот набран прописными, и VoiceOver читает такие
        /// строки по буквам, «эс-о-че-е-те-а-эн-и-я». Глазу разрядка
        /// и капитель нужны, уху — нет.
        var title: String {
            switch self {
            case .intro: return t("Знакомство")
            case .features: return t("Возможности")
            case .uses: return t("Чем пользуетесь")
            case .look: return t("Вид выреза")
            case .calendar: return t("Календарь")
            case .weather: return t("Погода и перерывы")
            case .ai: return t("Помощник")
            case .home: return t("Главный экран")
            case .controls: return t("Управление")
            case .permissions: return t("Доступы")
            case .done: return t("Готово")
            }
        }
    }

    /// Чем занято окно: рассказом о приложении или описанием выпусков.
    ///
    /// Режим, а не шестой шаг: шаги идут по порядку и ведут к «Начать»,
    /// а описание читают вразнобой и уходят из него обратно. Шестым шагом
    /// оно встало бы человеку поперёк знакомства, которое он и открыл.
    enum Mode: Equatable {
        case tour
        case notes
    }

    /// Раздел на шаге «Возможности».
    ///
    /// Сетка плиток на первом экране отвечает на «что это вообще умеет»
    /// одним взглядом — и больше ни на что: под словом «Полка» не угадать,
    /// что файлы на неё кладут перетаскиванием на чёлку. Плиток к тому же
    /// стало больше, чем помещается в ряд.
    ///
    /// Поэтому подробности — своим шагом, списком слева и описанием справа.
    /// Читают его вразнобой: человек ищет то, чего не понял, а не проходит
    /// подряд.
    enum Feature: String, CaseIterable, Identifiable {
        // Главный экран — первым: остальное на нём и живёт плитками.
        case home
        case music, calendar, meetings, capture, assistant, agent, voice
        case news, sites
        case notes, record, clipboard, shelf, windows, timer, breaks, countdown, monitor
        case teleprompter, weather, battery, caffeine

        var id: String { rawValue }

        var title: String {
            switch self {
            case .home: return t("Главный экран")
            case .music: return t("Музыка")
            case .calendar: return t("Календарь и задачи")
            case .meetings: return t("Встречи")
            case .capture: return t("Захват текста")
            case .assistant: return t("Помощник")
            // Коротко, потому что список узкий: «Помощник с действиями»
            // обрезался в нём многоточием, а обрезанное название перестаёт
            // быть названием. «Поручения» и короче, и точнее говорит, чем
            // это отличается от соседнего «Помощника».
            case .agent: return t("Поручения")
            case .voice: return t("Голос")
            case .news: return t("Сводка новостей")
            case .sites: return t("Слежка за сайтами")
            case .notes: return t("Заметки")
            case .record: return t("Запись разговора")
            case .clipboard: return t("Буфер обмена")
            case .shelf: return t("Полка")
            case .windows: return t("Окна")
            case .timer: return t("Таймер")
            case .breaks: return t("Перерывы")
            case .countdown: return t("Обратный отсчёт")
            case .monitor: return t("Нагрузка")
            case .teleprompter: return t("Телесуфлер")
            case .weather: return t("Погода")
            case .battery: return t("Батарея")
            case .caffeine: return t("Чашка кофе")
            }
        }

        var symbol: String {
            switch self {
            case .home: return "square.grid.3x2.fill"
            case .music: return "music.note"
            case .calendar: return "calendar"
            case .meetings: return "video.fill"
            case .capture: return "text.viewfinder"
            case .assistant: return "sparkles"
            case .agent: return "wand.and.stars"
            case .voice: return "waveform"
            case .news: return "newspaper"
            case .sites: return "binoculars"
            case .notes: return "list.bullet.rectangle"
            case .record: return "waveform.circle.fill"
            case .clipboard: return "doc.on.clipboard.fill"
            case .shelf: return "tray.full.fill"
            case .windows: return "rectangle.split.2x1.fill"
            case .timer: return "timer"
            case .breaks: return "figure.cooldown"
            case .countdown: return "hourglass"
            case .monitor: return "gauge.with.dots.needle.67percent"
            case .teleprompter: return "text.alignleft"
            case .weather: return "cloud.sun.fill"
            case .battery: return "bolt.fill"
            case .caffeine: return "cup.and.saucer.fill"
            }
        }

        /// Одна фраза о том, что это. Её видно рядом с названием в списке.
        var summary: String {
            switch self {
            case .home: return t("Соберите вырез из нужных плиток")
            case .music: return t("Что играет — прямо в вырезе")
            case .calendar: return t("Месяц, дела дня и правка события в вырезе")
            case .meetings: return t("Управление звонком, не переключаясь на вкладку")
            case .capture: return t("Выделенный текст — сразу в работу")
            case .assistant: return t("Вопрос модели без единого окна")
            case .agent: return t("Не только отвечает, но и делает")
            case .voice: return t("Спросить вслух и услышать ответ")
            case .news: return t("Главное по вашим темам — каждое утро")
            case .sites: return t("Скажет, когда на странице что-то изменится")
            case .notes: return t("Записи с именем от модели и поиском по смыслу")
            case .record: return t("Разговор становится заметкой с задачами")
            case .clipboard: return t("История копирований под рукой")
            case .shelf: return t("Файлы на чёлке: отложить, сжать, поделиться")
            case .windows: return t("Окно к чёлке — и оно разложено")
            case .timer: return t("Отсчёт виден, не занимая экрана")
            case .breaks: return t("Перерыв, вода и разминка — вовремя")
            case .countdown: return t("Сколько осталось до вашего события")
            case .monitor: return t("Процессор, память и диск одним взглядом")
            case .teleprompter: return t("Текст у самой камеры")
            case .weather: return t("Предупреждает о дожде заранее")
            case .battery: return t("Заряд и питание без строки меню")
            case .caffeine: return t("Экран не гаснет, пока горит чашка")
            }
        }

        /// Подробности: два-четыре предложения. Здесь и живёт то, чего
        /// не угадать по названию.
        var detail: String {
            switch self {
            case .home:
                return t("Раскрытый вырез — это сетка плиток: музыка, ближайшие встречи, месяц, таймер, обратный отсчёт, погода, нагрузка, новости, строка вопроса к ИИ, чашка кофе и другие. Плитка показывает главное и умеет главное — поставить на паузу, пустить таймер, зажечь чашку, — а нажатие по ней открывает полную панель. Состав, порядок и размер плиток — в настройках, в разделе «Главный экран»: плитки перетаскивают мышью, размер выбирают нажатием.")
            case .music:
                return t("Свёрнутый вырез показывает обложку и название трека. Свайп двумя пальцами поперёк острова переключает трек, не убирая курсор. Работает с Музыкой, Spotify и всем, что отдаёт сведения системе.")
            case .calendar:
                return t("Ближайшая встреча появляется в вырезе заранее, а перед началом остров раздвигается обратным отсчётом. Рядом задачи из Напоминаний и Things 3. ⌃⌥D открывает мини-календарь: месяц с номерами недель слева, дела выбранного дня справа. Нажатие по событию открывает его правку прямо в вырезе.")
            case .meetings:
                return t("Пока идёт встреча в браузере, наведение на вырез показывает кнопки: микрофон, камера, демонстрация, поднять руку, выйти. Там же переключение динамиков и микрофона и кнопка записи. Работает с Телемостом, Google Meet, Zoom и Teams.")
            case .capture:
                return t("⌃⌥C забирает выделенное в любом окне и открывает панель с ним. Ниже — список команд: перевести, исправить ошибки, пересказать. Команды свои, у каждой может быть своя модель и своя клавиша.")
            case .agent:
                return t("Помощнику можно давать поручения, а не только вопросы: «поставь таймер на двадцать минут», «что у меня завтра», «заведи встречу в пятницу в три», «напомни забрать посылку», «запиши, что нужно продлить страховку», «что я записывал про отпуск». Он сам выберет, чем это сделать, — календарём, напоминаниями, таймером, погодой или поиском по вашим записям. Всё, что он собирается записать, сперва показывается карточкой: «Создать» или «Отмена», — так что ошибку видно до того, как она попадёт в календарь. Включается в настройках, в разделе «Модель»; нужна модель, умеющая вызывать инструменты.")
            case .assistant:
                return t("Вопрос набирается прямо в вырезе, ответ идёт потоком. Модель местная — Ollama или совместимый сервер, — либо облачная по ключу. Ответ можно скопировать, вставить в текущее окно или сохранить заметкой. Если разрешить помощнику действовать, он поставит таймер, посмотрит календарь и погоду, а встречу, напоминание или заметку сперва покажет карточкой — «Создать» или «Отмена».")
            case .voice:
                return t("Модификатор, нажатый дважды, начинает слушать. Панель при этом не раскрывается: она закрыла бы то, чем вы заняты, — вместо неё оживает сам остров. Речь распознаётся на компьютере и наружу не уходит.")
            case .news:
                return t("Задайте темы — «космические запуски», «новинки кино» — или попросите модель предложить их, и выберите расписание, например каждый день в 10:00. Модель просмотрит новости за период и оставит по каждой теме до пяти главных, с источником и ссылкой. О готовой сводке скажет плашка, а метка в чёлке держится, пока вы её не откроете. Сводку можно отправить в заметки или сохранить файлом Markdown. Темы и расписание — в настройках, в разделе «Сводки».")
            case .sites:
                return t("Дайте ссылку на страницу и скажите словами, за чем следить: цена, наличие, дата, число мест, любая строка. Страница проверяется по расписанию, и когда значение изменится, вырез покажет плашку «было → стало» с кнопкой, открывающей сайт. Для чисел есть условия «стало меньше», «стало больше» и порог. Если сайт спрашивает, не робот ли вы, проверку можно пройти один раз в окне приложения.")
            case .notes:
                return t("⌃⌥Z открывает пустую заметку, ⌃⌥⇧Z записывает выделенное, не открывая ничего. Имя придумывает модель. Поиск идёт по смыслу, а не по словам, и умеет искать по хранилищу Obsidian, если синхронизация включена.")
            case .record:
                return t("Кнопка в панели встречи пишет и вас, и собеседников; ⌃⌥R — только вас. Сказанное переводится в текст на самом компьютере и ложится заметкой: название, пересказ и задачи отдельным списком. Запись прикладывается к заметке и играет прямо из списка.")
            case .clipboard:
                return t("Приложение помнит скопированное — текст, ссылки и картинки. ⌃⌥V открывает историю, цифры вставляют нужную запись. Пароли из менеджеров и служебные копирования не сохраняются.")
            case .shelf:
                return t("Ведите файлы на чёлку — вырез раскроется разделами. «На полку» откладывает файлы, чтобы вытащить их в другом окне. «Сжать в ZIP» собирает архив рядом, а над архивами раздел распаковывает. «Ссылка iCloud» кладёт копию в iCloud Drive и копирует ссылку на неё. «В Корзину» — без открытия Finder.")
            case .windows:
                return t("Потащите окно за заголовок к чёлке — она покажет раскладки. Посередине весь экран и окно по центру на 85%, по бокам зеркально половина, две трети, треть и четверти. Отпустите окно на нужной — оно встанет по месту. Работает с окнами любых приложений; нужен Универсальный доступ.")
            case .breaks:
                return t("Задайте, как часто напоминать сделать перерыв, попить воды и размяться. Считается только время за компьютером: ушли на обед — счёт не идёт. Вместе с напоминанием из чёлки выходит котик и показывает, что делать; напоминание ждёт, пока вы не нажмёте «Готово» или «Пропустить». Промежутки — в настройках, в разделе «Инструменты».")
            case .countdown:
                return t("Плитка главного экрана с названием вашего события и тем, сколько до него осталось: дни и часы, а в последние сутки — с секундами. Когда событие наступит, вырез покажет плашку и выпустит конфетти. Событие задают в настройках, в разделе «Главный экран».")
            case .timer:
                return t("⌃⌥T открывает таймер и секундомер. Пока идёт отсчёт, чёлка раздвигается счётом — нажатие по нему возвращает панель. По окончании звучит сигнал и предлагается перерыв.")
            case .monitor:
                return t("⌃⌥M показывает загрузку процессора, занятую память и место на диске. Нажатие по плитке открывает Мониторинг системы.")
            case .teleprompter:
                return t("⌃⌥P разворачивает текст под чёлкой — там, где стоит камера. С оформлением и автопрокруткой: читая с середины экрана, смотришь мимо объектива, и это видно собеседнику.")
            case .weather:
                return t("Вырез предупреждает о дожде и снеге заранее, а при смене погоды из чёлки капает дождь, сыплется снег или всплывает солнце. Температура — плиткой на главном экране или значком в его углу. Место берётся по геопозиции или называется вручную; наружу уходят только округлённые координаты.")
            case .battery:
                return t("Подключение и отключение питания видно плашкой, низкий заряд — предупреждением. Порог настраивается.")
            case .caffeine:
                return t("Чашка не даёт экрану гаснуть заданный срок. Пока она горит, вырез раздвинут полоской с остатком времени.")
            }
        }
        /// Случай из жизни — по одному на функцию.
        ///
        /// Отдельно от `detail`, а не припиской к нему: описание отвечает
        /// «что это», а пример — «когда мне это понадобится», и на второй
        /// вопрос человек смотрит первым. Слитые в один абзац, они читаются
        /// как продолжение объяснения, и пример теряется в нём.
        var example: String {
            switch self {
            case .home:
                return t("Весь день работаете с таймером и следите за новостями: поставьте их плитками рядом с музыкой — одно наведение на чёлку, и всё перед глазами.")
            case .music:
                return t("Слушаете музыку и не помните, что за трек: ведёте курсор к чёлке — название и обложка на месте, двумя пальцами вбок — следующий.")
            case .calendar:
                return t("Созвон через десять минут: вырез сам покажет отсчёт и кнопку со ссылкой — искать письмо с приглашением не нужно.")
            case .meetings:
                return t("Забыли выключить микрофон, уходя за чаем: кнопка микрофона в вырезе — не нужно искать окно встречи среди десятка других.")
            case .capture:
                return t("Пришло письмо на английском: выделили абзац, ⌃⌥C, «Перевести» — перевод рядом, а вставить его можно прямо в ответ.")
            case .agent:
                return t("Договорились о встрече в переписке: выделили сообщение и сказали «заведи встречу» — карточка покажет день и время, вам остаётся нажать «Создать».")
            case .assistant:
                return t("Застряли на формулировке в письме: спросили прямо из чёлки и вставили ответ в то же поле, не переключая окон.")
            case .voice:
                return t("Руки в тесте, а вспомнить нужно: «что у меня сегодня» — и вырез отвечает вслух, ничего не закрывая на экране.")
            case .news:
                return t("Утром некогда листать ленты: в десять вырез скажет, что сводка готова, — пять пунктов по теме и ссылка на каждый.")
            case .sites:
                return t("Ждёте, когда откроется запись на курс: укажите страницу и «число свободных мест» — вырез скажет, как только оно изменится.")
            case .notes:
                return t("Мысль пришла посреди работы: ⌃⌥Z, две строки — и назад. Имя записи придумает модель, искать потом можно по смыслу, а не по словам.")
            case .record:
                return t("Созвон на сорок минут: включили запись, после неё в заметках лежит пересказ, список задач и полная расшифровка.")
            case .clipboard:
                return t("Скопировали код из письма, потом ссылку, потом адрес — и всё это нужно вставить: ⌃⌥V показывает последние копирования, ⌃⌥1 вставляет предпоследнее.")
            case .shelf:
                return t("Нужно отправить папку с макетами: перетащили на чёлку в «Ссылку iCloud» — ссылка уже в буфере, остаётся вставить её в письмо.")
            case .windows:
                return t("Сравниваете два документа: первый к чёлке на левую половину, второй — на правую, и оба перед глазами без возни с краями окон.")
            case .breaks:
                return t("Засиделись над задачей три часа подряд: вырез напомнит размяться, котик покажет зарядку, а отложить можно одной кнопкой.")
            case .countdown:
                return t("Ждёте отпуска: плитка «Отпуск — 12 дн 4 ч» на главном экране, а в день вылета — конфетти из чёлки.")
            case .timer:
                return t("Поставили чайник и вернулись к работе: счёт видно прямо в чёлке, а сигнал прозвучит, даже если окно таймера давно закрыто.")
            case .monitor:
                return t("Вентилятор завыл на пустом месте: ⌃⌥M — и видно, что именно упёрлось: процессор, память или диск.")
            case .teleprompter:
                return t("Записываете видео и хотите смотреть в камеру: текст идёт под чёлкой, у самого объектива, а не внизу экрана.")
            case .weather:
                return t("Собираетесь выйти: вырез сам скажет, что через час дождь, — до того, как вы оденетесь.")
            case .battery:
                return t("Работаете от батареи: вырез предупредит о низком заряде сам, а не тихой плашкой в углу, которую легко пропустить.")
            case .caffeine:
                return t("Показываете презентацию: нажали чашку на час — экран не погаснет посреди слайда, и выключать заставку насовсем не придётся.")
            }
        }
    }

    @Published var mode: Mode = .tour
    @Published var step: Step = .intro
    @Published var feature: Feature = .home
    /// Доступы — общим узлом с настройками: см. `PermissionCenter`.
    let permissions: PermissionCenter
    typealias Permission = PermissionCenter.Permission
    typealias PermissionState = PermissionCenter.State
    private var permissionsForwarding: AnyCancellable?

    private let calendar: CalendarService
    private let settings: Settings

    init(calendar: CalendarService, settings: Settings = .shared) {
        self.calendar = calendar
        self.settings = settings
        permissions = PermissionCenter(calendar: calendar, settings: settings)
        permissionsForwarding = permissions.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    // MARK: - Жизненный цикл

    /// Доступы выдаются в Системных настройках, за пределами приложения,
    /// и уведомления об этом не приходит. Пока окно открыто — опрашиваем.
    func start(mode: Mode = .tour) {
        self.mode = mode
        step = .intro
        // Отладочный вход: кликать по кнопкам из сессии нечем, а снимать
        // нужно все четыре шага.
        //   defaults write com.trunook.Trunook debugWelcomeStep 2
        if DebugLog.isEnabled,
           let forced = Step(rawValue: UserDefaults.standard.integer(forKey: "debugWelcomeStep")) {
            step = forced
        }
        //   defaults write com.trunook.Trunook debugWelcomeFeature news
        if DebugLog.isEnabled,
           let name = UserDefaults.standard.string(forKey: "debugWelcomeFeature"),
           let forced = Feature(rawValue: name) {
            feature = forced
        }
        permissions.start()
    }

    func stop() {
        permissions.stop()
    }


    // MARK: - Шаги

    /// Надпись над заголовком. В режиме описания она своя: шага там нет.
    var eyebrow: String {
        mode == .notes ? t("ОПИСАНИЕ") : step.eyebrow
    }

    func toggleNotes() {
        mode = mode == .notes ? .tour : .notes
        Haptics.tap()
    }

    /// Шаги, которые видит этот человек: по тому, что он отметил.
    var steps: [Step] { WelcomeFlow.steps(uses: WelcomeFlow.uses(in: settings)) }

    var canGoBack: Bool { step != .intro }
    var isLastStep: Bool { step == .done }

    func next() {
        let visible = steps
        // Шаг мог пропасть из списка, пока на нём стоят, — сняли отметку
        // на «Чем пользуетесь» и вернулись: идём к ближайшему следующему.
        guard let following = visible.first(where: { $0.rawValue > step.rawValue }) else { return }
        go(to: following)
    }

    func back() {
        guard let previous = steps.last(where: { $0.rawValue < step.rawValue }) else { return }
        go(to: previous)
    }

    func go(to target: Step) {
        guard target != step else { return }
        step = target
        Haptics.tap()
    }

    // MARK: - Доступы

    func state(of permission: Permission) -> PermissionState { permissions.state(of: permission) }
    func actionTitle(for permission: Permission) -> String { permissions.actionTitle(for: permission) }
    func act(on permission: Permission) { permissions.act(on: permission) }
    func isRequired(_ permission: Permission) -> Bool { permissions.isRequired(permission) }
    var pendingCount: Int { permissions.pendingCount }
}
