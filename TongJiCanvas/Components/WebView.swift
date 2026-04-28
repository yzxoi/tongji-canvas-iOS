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
