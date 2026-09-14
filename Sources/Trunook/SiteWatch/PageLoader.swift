import TrunookXPC
import AppKit
import WebKit

/// Что удалось вынуть со страницы.
struct PageSnapshot: Equatable {
    var title: String
    var text: String
    /// Цена из разметки для поисковиков (`application/ld+json`), если есть.
    var price: String?
    var currency: String?
}

/// Открывает страницу настоящим WebKit и вынимает из неё текст.
///
/// Не `URLSession`: магазины отдают простому запросу пустую заготовку или
/// проверку на робота, а цену дорисовывают скриптом. Проба на Озоне
/// показала оба случая сразу — 403 с JS-проверкой на запрос и страницу
/// «нет соединения» браузеру через VPN.
///
/// Вид живёт в невидимом окне за краем экрана: без окна часть страниц
/// не доигрывает скрипты. Окно в одну точку, прозрачное и стоит в списке
/// окон только на время загрузки: при перестройке экранов macOS переносит
/// окна, не попавшие ни на один экран, на основной, и пустой WebKit висел
/// белым листом 1280×900 поверх рабочего стола.
///
/// Хранилище данных постоянное — пройденная руками проверка оставляет куки,
/// и следующие загрузки идут с ними.
final class PageLoader: NSObject, WKNavigationDelegate {
    nonisolated static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    /// После `didFinish` скрипты магазина ещё дорисовывают цену.
    private static let settle: TimeInterval = 4
    private static let timeout: TimeInterval = 30
    private static let textLimit = 12_000

    private static let extractScript = """
        (() => {
          let price = null, currency = null;
          const walk = (node) => {
            if (!node || price !== null) return;
            if (Array.isArray(node)) { node.forEach(walk); return; }
            if (typeof node !== 'object') return;
            const offers = node.offers;
            if (offers) {
              const offer = Array.isArray(offers) ? offers[0] : offers;
              const value = offer && (offer.price ?? offer.lowPrice);
              if (value !== undefined && value !== null) {
                price = String(value); currency = offer.priceCurrency || null; return;
              }
            }
            if (node['@graph']) walk(node['@graph']);
          };
          document.querySelectorAll('script[type="application/ld+json"]').forEach((s) => {
            try { walk(JSON.parse(s.textContent)); } catch (e) {}
          });
          const text = document.body ? document.body.innerText : '';
          return [document.title || '', text.slice(0, \(textLimit)), price, currency];
        })()
        """

    private var window: NSWindow?
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<PageSnapshot?, Never>?
    private var deadline: DispatchWorkItem?
    private var settling: DispatchWorkItem?
    private var screensObserver: NSObjectProtocol?

    private static let offscreen = NSPoint(x: -10_000, y: -10_000)

    @MainActor
    func load(_ url: URL) async -> PageSnapshot? {
        // Одна страница за раз: слежки идут очередью, и вторая загрузка
        // поверх первой перебила бы ей навигацию.
        guard continuation == nil else { return nil }
        let webView = prepare()
        window?.setFrameOrigin(Self.offscreen)
        window?.orderBack(nil)
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let deadline = DispatchWorkItem { [weak self] in
                DebugLog.write("слежка: страница не загрузилась за \(Int(Self.timeout)) с")
                self?.extract()
            }
            self.deadline = deadline
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout, execute: deadline)
            webView.load(URLRequest(url: url))
        }
    }

    private func prepare() -> WKWebView {
        if let webView { return webView }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let frame = NSRect(x: 0, y: 0, width: 1280, height: 900)
        let webView = WKWebView(frame: frame, configuration: configuration)
        webView.customUserAgent = Self.userAgent
        webView.navigationDelegate = self

        let window = NSWindow(
            contentRect: NSRect(origin: Self.offscreen, size: NSSize(width: 1, height: 1)),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.alphaValue = 0
        // Окно в точку, а вид страницы — во весь размер: по ширине вида
        // магазин выбирает вёрстку, и узкий получил бы мобильную.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        container.addSubview(webView)
        window.contentView = container
        // Экраны перестроились посреди загрузки — вернуть окно за край.
        screensObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak window] _ in
            window?.setFrameOrigin(Self.offscreen)
        }
        self.window = window
        self.webView = webView
        return webView
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Проверка на робота переадресует ещё раз, и `didFinish` приходит
        // дважды. Ждём тишины после последнего. Без ожидающего — это пустая
        // страница, которой закрыли прошлую загрузку.
        guard continuation != nil else { return }
        settling?.cancel()
        let settling = DispatchWorkItem { [weak self] in self?.extract() }
        self.settling = settling
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settle, execute: settling)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        failed(error)
    }

    private func failed(_ error: Error) {
        // Отменённая навигация — это переадресация, а не сбой.
        if (error as NSError).code == NSURLErrorCancelled { return }
        DebugLog.write("слежка: страница не открылась — \(error.localizedDescription)")
        complete(nil)
    }

    private func extract() {
        guard continuation != nil, let webView else { return }
        webView.evaluateJavaScript(Self.extractScript) { [weak self] result, error in
            guard let self else { return }
            guard let values = result as? [Any], values.count == 4 else {
                DebugLog.write("слежка: текст страницы не вынулся — \(error?.localizedDescription ?? "пусто")")
                self.complete(nil)
                return
            }
            self.complete(PageSnapshot(
                title: values[0] as? String ?? "",
                text: values[1] as? String ?? "",
                price: values[2] as? String,
                currency: values[3] as? String
            ))
        }
    }

    private func complete(_ snapshot: PageSnapshot?) {
        deadline?.cancel()
        settling?.cancel()
        deadline = nil
        settling = nil
        guard let continuation else { return }
        self.continuation = nil
        webView?.stopLoading()
        // Пустая страница вместо ушедшей: иначе скрипты магазина крутились бы
        // в невидимом окне до следующей проверки.
        webView?.loadHTMLString("", baseURL: nil)
        window?.orderOut(nil)
        continuation.resume(returning: snapshot)
    }
}

/// Окно, где человек сам проходит проверку сайта.
///
/// То же хранилище данных, что у фоновой загрузки: куки, полученные здесь,
/// достаются и ей. Другого честного пути мимо проверки на робота нет —
/// и искать его не надо.
final class SiteVerifyWindow: NSObject, NSWindowDelegate {
    static let shared = SiteVerifyWindow()

    private var window: NSWindow?

    func open(_ url: URL, title: String) {
        let window = self.window ?? makeWindow()
        window.title = title
        (window.contentView as? WKWebView)?.load(URLRequest(url: url))
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    private func makeWindow() -> NSWindow {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 800), configuration: configuration)
        webView.customUserAgent = PageLoader.userAgent
        let window = NSWindow(
            contentRect: webView.frame,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.delegate = self
        return window
    }

    func windowWillClose(_ notification: Notification) {
        (window?.contentView as? WKWebView)?.loadHTMLString("", baseURL: nil)
    }
}
