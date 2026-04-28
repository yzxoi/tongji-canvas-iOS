import SwiftUI
import WebKit

// MARK: - View

struct LoginView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var repo: SessionRepository
    @StateObject private var vm = LoginViewModel()

    var onSaved: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                tipCard

                Picker("模式", selection: Binding(get: { vm.isMobileUA }, set: { vm.switchUA(toMobile: $0) })) {
                    Label("移动端", systemImage: "iphone").tag(true)
                    Label("桌面端", systemImage: "desktopcomputer").tag(false)
                }
                .pickerStyle(.segmented)

                HStack(spacing: 12) {
                    statusChip(
                        icon: "link",
                        label: vm.currentURL.isEmpty ? "等待加载..." : "已加载"
                    )
                    statusChip(
                        icon: vm.loginDetected ? "checkmark.shield" : "clock",
                        label: vm.loginDetected
                            ? (vm.countdown > 0 ? "倒计时 \(vm.countdown)s" : "已捕获")
                            : "等待登录"
                    )
                }

                LoginWebViewWrapper(vm: vm)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .top) {
                        if !vm.loginDetected {
                            ProgressView()
                                .progressViewStyle(.linear)
                                .tint(Color(hex: 0x7C3AED))
                                .padding(.top, -2)
                        }
                    }

                Text(vm.statusMessage)
                    .font(.caption)
                    .foregroundStyle(vm.loginDetected ? .blue : Color(.secondaryLabel))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .padding(.top, 4)
            .navigationTitle("统一认证登录")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .onAppear {
            vm.repo = repo
            vm.onSaved = {
                onSaved()
                dismiss()
            }
        }
    }

    private var tipCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("操作提示").font(.subheadline.weight(.semibold))
            Text("1. 使用统一认证账号登录 Canvas，系统会自动捕获 Cookies。")
                .font(.caption).foregroundStyle(.secondary)
            Text("2. 若页面显示异常，可切换上方模式以匹配移动或桌面站点。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func statusChip(icon: String, label: String) -> some View {
        Label(label, systemImage: icon)
            .font(.caption)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
    }
}

// MARK: - WebView wrapper for login

struct LoginWebViewWrapper: UIViewRepresentable {
    let vm: LoginViewModel

    func makeCoordinator() -> Coordinator { Coordinator(vm: vm) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = true
        vm.configureWebView(wv)
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        let vm: LoginViewModel
        init(vm: LoginViewModel) { self.vm = vm }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = action.request.url { vm.handleURLChange(url) }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            if let url = webView.url { vm.handleURLChange(url) }
        }
    }
}

