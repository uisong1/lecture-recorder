import LectureCore
import SwiftUI
import WebKit

/// 앱 안 LMS 창의 웹뷰. 사용자가 평소처럼 SSO로 로그인하고, 로그인 정보는 웹뷰의 쿠키 저장소에만 남는다 (앱이 비밀번호를 저장하지 않는다).
/// 강의 영상을 열면 페이지가 요청하는 `screen.mp4` 주소를 알아내 `LMSImportModel`에 넘긴다.
@MainActor
@Observable
final class LMSBrowser: NSObject {
    static let homeURL = URL(string: "https://canvas.ssu.ac.kr")!
    static let messageName = "lmsVideo"

    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isLoading = false
    private(set) var currentURL: URL?
    /// 영상이 안 잡힐 때 원인을 볼 수 있게, 웹 페이지 안에서 본 프레임과 미디어 주소(쿼리 제외)를 모아 둔다.
    private(set) var diagnostics = LMSDiagnostics()

    /// 영상 주소를 알려 줄 곳. 앱을 조립할 때 연결한다.
    @ObservationIgnored weak var model: LMSImportModel?
    @ObservationIgnored private var pageCourseName: String?
    @ObservationIgnored private var observers: [NSKeyValueObservation] = []

    /// 로그인 상태가 이 웹뷰의 기본 저장소에 남도록 `.default()`를 쓴다. 앱을 껐다 켜도 만료되기 전까지 유지된다.
    @ObservationIgnored let webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        return WKWebView(frame: .zero, configuration: configuration)
    }()

    override init() {
        super.init()
        let script = WKUserScript(source: Self.detectionScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        webView.configuration.userContentController.addUserScript(script)
        webView.configuration.userContentController.add(MessageForwarder(owner: self), name: Self.messageName)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        // 웹뷰의 상태가 바뀔 때마다 버튼 상태를 다시 읽는다.
        func observe<Value>(_ keyPath: KeyPath<WKWebView, Value>) -> NSKeyValueObservation {
            webView.observe(keyPath, options: [.initial, .new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.syncState() }
            }
        }
        observers = [observe(\.canGoBack), observe(\.canGoForward), observe(\.isLoading), observe(\.url)]
    }

    private func syncState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        currentURL = webView.url
    }

    /// 창을 처음 열 때 한 번만 LMS 첫 화면을 불러온다.
    func loadHomeIfNeeded() {
        guard webView.url == nil, !webView.isLoading else { return }
        webView.load(URLRequest(url: Self.homeURL))
    }

    func goHome() { webView.load(URLRequest(url: Self.homeURL)) }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }

    /// 이 주소에 보낼 쿠키를 웹뷰 저장소에서 꺼내 `Cookie` 헤더 값으로 만든다. 도메인·경로가 맞는 것만 담긴다.
    func cookieHeader(for url: URL) async -> String? {
        let cookies = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let converted = cookies.map {
            LMSCookie(name: $0.name, value: $0.value, domain: $0.domain, path: $0.path, isSecure: $0.isSecure, expires: $0.expiresDate)
        }
        return LMSCookie.header(for: url, cookies: converted)
    }

    fileprivate func received(body: Any) {
        guard let body = body as? [String: Any], let report = LMSMediaReport(body: body) else { return }
        diagnostics.record(report.summary)
        if let candidate = report.candidate(courseName: pageCourseName) { model?.captured(candidate) }
    }

    /// 페이지를 다 불러오면 강의명을 읽어 둔다. 영상이 먼저 잡혔다면 비어 있던 강의명을 채운다.
    private func readCourseName() {
        webView.evaluateJavaScript(Self.courseNameScript) { [weak self] result, _ in
            MainActor.assumeIsolated {
                guard let self, let name = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return }
                self.pageCourseName = name
                self.model?.updateCourseNameIfEmpty(name)
            }
        }
    }

    /// 모든 프레임에서 미디어 주소를 지켜보다가 알린다 (본편 판별은 앱 쪽에서 한다).
    /// 영상은 보통 iframe 안의 `<video>`가 직접 요청하는데 WebKit은 그 요청을 자원 목록에 남기지 않아서,
    /// `<video>`/`<source>`(열린 shadow DOM 포함)를 주기적으로 읽고 미디어 이벤트·`src` 설정·`fetch`·`XHR`도 함께 본다.
    /// `fetch`와 `XHR`는 주소만 확인하고 그대로 넘겨서 페이지 동작은 바꾸지 않는다.
    private static let detectionScript = #"""
    (function () {
      if (window.__lectureRecorderHooked) return;
      window.__lectureRecorderHooked = true;
      var seen = {};
      var MEDIA = /\.(mp4|m4v|m4a|mp3|webm|m3u8|mpd)(\?|#|$)/i;
      function post(message) { try { window.webkit.messageHandlers.lmsVideo.postMessage(message); } catch (e) {} }
      function report(u, via) {
        if (!u || typeof u !== 'string') return;
        var a = u;
        if (u.indexOf('blob:') !== 0 && u.indexOf('data:') !== 0) {
          try { a = new URL(u, location.href).href; } catch (e) { return; }
          if (!MEDIA.test(a)) return;
        }
        if (seen[a]) return;
        seen[a] = true;
        post({ kind: 'media', url: a, page: location.href, via: via });
      }
      function scanRoot(root, deep) {
        var els = root.querySelectorAll('video, audio, source');
        for (var i = 0; i < els.length; i++) { report(els[i].currentSrc || els[i].src || els[i].getAttribute('src'), 'element'); }
        if (!deep) return;
        var all = root.querySelectorAll('*');
        for (var j = 0; j < all.length; j++) { if (all[j].shadowRoot) scanRoot(all[j].shadowRoot, true); }
      }
      post({ kind: 'frame', url: location.href, page: location.href, via: window === window.top ? 'top' : 'iframe' });
      try { var f = window.fetch; if (f) window.fetch = function (i) { try { report(typeof i === 'string' ? i : (i && i.url), 'fetch'); } catch (e) {} return f.apply(this, arguments); }; } catch (e) {}
      try { var o = XMLHttpRequest.prototype.open; XMLHttpRequest.prototype.open = function (m, u) { try { report(String(u), 'xhr'); } catch (e) {} return o.apply(this, arguments); }; } catch (e) {}
      try {
        var d = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
        if (d && d.set) Object.defineProperty(HTMLMediaElement.prototype, 'src', { configurable: true, enumerable: d.enumerable, get: d.get, set: function (v) { try { report(v, 'src-setter'); } catch (e) {} return d.set.call(this, v); } });
      } catch (e) {}
      ['loadstart', 'loadedmetadata', 'durationchange', 'play', 'playing'].forEach(function (name) {
        window.addEventListener(name, function (e) { var t = e.target; if (t && t.currentSrc !== undefined) report(t.currentSrc || t.src, 'event'); }, true);
      });
      try { new MutationObserver(function () { scanRoot(document, false); }).observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: ['src'] }); } catch (e) {}
      var ticks = 0;
      setInterval(function () { try { scanRoot(document, ticks++ % 4 === 0); } catch (e) {} }, 1500);
      scanRoot(document, false);
    })();
    """#

    /// 강의명 후보: Canvas의 현재 강의 정보, 이동 경로(breadcrumb)의 두 번째 칸, 마지막으로 제목의 `: ` 뒤. 틀릴 수 있어 사용자가 고칠 수 있다.
    private static let courseNameScript = #"""
    (function () {
      try { var c = window.ENV && window.ENV.current_context; if (c && c.name) return String(c.name); } catch (e) {}
      try { var li = document.querySelectorAll('#breadcrumbs li'); if (li.length > 1) return li[1].innerText.trim(); } catch (e) {}
      var parts = (document.title || '').split(': ');
      return parts.length > 1 ? parts[parts.length - 1] : '';
    })();
    """#
}

/// 웹뷰가 스크립트 핸들러를 강하게 붙들어서 생기는 순환 참조를 피하려고 약하게 전달만 한다.
private final class MessageForwarder: NSObject, WKScriptMessageHandler {
    weak var owner: LMSBrowser?

    init(owner: LMSBrowser) { self.owner = owner }

    @MainActor
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.received(body: message.body)
    }
}

extension LMSBrowser: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // 웹 주소만 연다. 다른 앱을 여는 주소 등은 막는다.
        let scheme = navigationAction.request.url?.scheme?.lowercased() ?? ""
        if navigationAction.targetFrame?.isMainFrame == false, let url = navigationAction.request.url, let host = url.host() {
            diagnostics.record("하위 프레임 이동: \(host)\(url.path)")
        }
        decisionHandler(["http", "https", "about", "blob", "data"].contains(scheme) ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        // 다른 페이지로 가면 이전 페이지의 영상 후보는 버린다. 새 페이지가 영상을 띄우면 다시 잡힌다.
        pageCourseName = nil
        diagnostics.clear()
        model?.clearCandidate()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        readCourseName()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Log.app.error("LMS 페이지 불러오기 실패: \(error.localizedDescription, privacy: .public)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Log.app.error("LMS 페이지 불러오기 실패: \(error.localizedDescription, privacy: .public)")
    }

    /// 새 창으로 열리는 링크(`target=_blank`)도 이 창에서 연다.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }
}

struct LMSWebView: NSViewRepresentable {
    let browser: LMSBrowser

    func makeNSView(context: Context) -> WKWebView { browser.webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
