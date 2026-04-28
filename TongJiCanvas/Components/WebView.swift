import SwiftUI
import WebKit

// MARK: - Generic WKWebView wrapper

struct WebViewRepresentable: UIViewRepresentable {
    let configuration: WKWebViewConfiguration
    let request: URLRequest
    var userAgent: String? = nil
    var onURLChange: ((URL) -> Void)? = nil
    var onPageFinish: ((WKWebView, URL?) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let wv = WKWebView(frame: .zero, configuration: configuration)
        wv.navigationDelegate = context.coordinator
        if let ua = userAgent { wv.customUserAgent = ua }
        wv.load(request)
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebViewRepresentable

        init(_ parent: WebViewRepresentable) { self.parent = parent }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
            parent.onURLChange?(webView.url ?? URL(string: "about:blank")!)
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            parent.onPageFinish?(webView, webView.url)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            parent.onURLChange?(action.request.url ?? URL(string: "about:blank")!)
            decisionHandler(.allow)
        }
    }
}

// MARK: - Silent signing WebView (no UI, result via async)

@MainActor
final class SigningWebView: NSObject, WKNavigationDelegate {
    private let webView: WKWebView

    init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func sign(url: URL) async -> Bool {
        let req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        webView.load(req)
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    private var continuation: CheckedContinuation<Bool, Never>?

    nonisolated func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        Task { @MainActor in
            let result = try? await webView.evaluateJavaScript("document.body.innerText || ''")
            let text = result as? String ?? ""
            let ok = text.contains("签到成功") || text.contains("已签过") || text.contains("签到已完成")
            self.continuation?.resume(returning: ok)
            self.continuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail _: WKNavigation!, withError _: Error) {
        Task { @MainActor in
            self.continuation?.resume(returning: false)
            self.continuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError _: Error) {
        Task { @MainActor in
            self.continuation?.resume(returning: false)
            self.continuation = nil
        }
    }
}
