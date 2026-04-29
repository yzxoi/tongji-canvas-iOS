import SwiftUI
import WebKit

@MainActor
final class LoginViewModel: NSObject, ObservableObject {
    @Published var currentURL    = ""
    @Published var loginDetected = false
    @Published var countdown     = 0
    @Published var isMobileUA    = true
    @Published var statusMessage = "Complete IAM authentication below. Cookies will be captured automatically."

    let loginURL = URL(string: "https://canvas.tongji.edu.cn/lms/mobile/forscan?courseCode=2333&rollCallToken=2333")!

    var webView: WKWebView?
    var onSaved: () -> Void = {}
    var repo: SessionRepository?

    private var countdownTask: Task<Void, Never>?
    private var hasVisitedNonCanvas = false

    let mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/120.0.0.0 Mobile/15E148 Safari/604.1"
    let desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    var currentUA: String { isMobileUA ? mobileUA : desktopUA }

    func configureWebView(_ wv: WKWebView) {
        webView = wv
        wv.customUserAgent = currentUA
        clearAndLoad()
    }

    func switchUA(toMobile: Bool) {
        guard isMobileUA != toMobile else { return }
        isMobileUA = toMobile
        guard let wv = webView else { return }
        wv.customUserAgent = currentUA
        loginDetected = false
        countdown = 0
        countdownTask?.cancel()
        clearAndLoad()
    }

    private func clearAndLoad() {
        guard let wv = webView else { return }
        hasVisitedNonCanvas = false
        loginDetected = false
        let store = wv.configuration.websiteDataStore.httpCookieStore
        store.getAllCookies { [weak self, weak wv] cookies in
            guard let self, let wv else { return }
            let group = DispatchGroup()
            for cookie in cookies {
                group.enter()
                store.delete(cookie) { group.leave() }
            }
            group.notify(queue: .main) {
                wv.load(URLRequest(url: self.loginURL,
                                   cachePolicy: .reloadIgnoringLocalAndRemoteCacheData))
            }
        }
    }

    func handleURLChange(_ url: URL) {
        currentURL = url.absoluteString
        let s = url.absoluteString

        let isCanvas   = s.hasPrefix("https://canvas.tongji.edu.cn/")
        let isAuthPage = s.contains("login") || s.contains("oauth2") ||
                         s.contains("openid_connect") || s.contains("saml")

        if !isCanvas || isAuthPage {
            hasVisitedNonCanvas = true
        }

        if isCanvas && !isAuthPage && hasVisitedNonCanvas && !loginDetected {
            loginDetected = true
            startCountdown()
        }
    }

    private func startCountdown() {
        statusMessage = ""
        countdownTask = Task { @MainActor in
            for i in stride(from: 1, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                countdown = i
                statusMessage = "Authentication detected. Capturing credential in \(i)s..."
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            countdown = 0
            statusMessage = "Extracting credential..."
            await extractAndSave()
        }
    }

    private func extractAndSave() async {
        guard let wv = webView, let repo = repo else { return }
        let cookieString = await CookieHelper.captureCanvasCookies(
            from: wv.configuration.websiteDataStore.httpCookieStore
        )
        guard !cookieString.isEmpty else {
            statusMessage = "No credential found. Please try again."
            loginDetected = false
            hasVisitedNonCanvas = false
            return
        }
        let displayName = await extractUserInfo(from: wv)
        repo.addOrUpdate(displayName: displayName, accessToken: cookieString)
        onSaved()
    }

    /// Extract student name and ID from the loaded response HTML.
    /// Falls back to a timestamp-based ID if parsing fails.
    private func extractUserInfo(from wv: WKWebView) async -> String {
        let js = """
        (function() {
            const content = document.querySelector('.content.nomsg');
            if (!content) return null;
            const divs = content.querySelectorAll('div');
            var sid = '', name = '';
            divs.forEach(function(div) {
                var text = div.textContent.trim();
                if (text.indexOf('学号/工号：') === 0) sid = text.split('：')[1].trim();
                if (text.indexOf('签到人员：') === 0) name = text.split('：')[1].trim();
            });
            if (!name && !sid) return null;
            return JSON.stringify({sid: sid, name: name});
        })()
        """
        do {
            let result = try await wv.evaluateJavaScript(js)
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String]
            else { return "id_\(Int(Date().timeIntervalSince1970))" }
            var parts: [String] = []
            if let name = obj["name"], !name.isEmpty { parts.append(name) }
            if let sid = obj["sid"], !sid.isEmpty { parts.append(sid) }
            return parts.isEmpty ? "id_\(Int(Date().timeIntervalSince1970))" : parts.joined(separator: "_")
        } catch {
            return "id_\(Int(Date().timeIntervalSince1970))"
        }
    }
}
