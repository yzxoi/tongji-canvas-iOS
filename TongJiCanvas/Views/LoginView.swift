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

                Picker("Mode", selection: Binding(get: { vm.isMobileUA }, set: { vm.switchUA(toMobile: $0) })) {
                    Label("Mobile", systemImage: "iphone").tag(true)
                    Label("Desktop", systemImage: "desktopcomputer").tag(false)
                }
                .pickerStyle(.segmented)

                HStack(spacing: 12) {
                    statusChip(
                        icon: "link",
                        label: vm.currentURL.isEmpty ? "Loading..." : "Loaded"
                    )
                    statusChip(
                        icon: vm.loginDetected ? "checkmark.shield" : "clock",
                        label: vm.loginDetected
                            ? (vm.countdown > 0 ? "Capture in \(vm.countdown)s" : "Captured")
                            : "Awaiting login"
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
                    .foregroundStyle(vm.loginDetected ? Color(hex: 0x7C3AED) : Color(.secondaryLabel))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .padding(.top, 4)
            .navigationTitle("IAM Authentication")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
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
        HStack(alignment: .top, spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(Palette.accentSurface)
                    .frame(width: 32, height: 32)
                Image(systemName: "info.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.accent)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Instructions")
                    .font(.subheadline.weight(.semibold))
                Text("Sign in with your university IAM account — cookies are captured automatically. Switch UA modes if the page renders incorrectly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.md)
        .background(Palette.accentSurface.opacity(0.5), in: RoundedRectangle(cornerRadius: Radius.inner))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.inner)
                .strokeBorder(Palette.accent.opacity(0.15), lineWidth: 1)
        )
    }

    private func statusChip(icon: String, label: String) -> some View {
        Label(label, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground), in: Capsule())
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
                     preferences: WKWebpagePreferences,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
            if let url = action.request.url { vm.handleURLChange(url) }
            decisionHandler(.allow, preferences)
        }

        func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
            if let url = webView.url { vm.handleURLChange(url) }
        }
    }
}
