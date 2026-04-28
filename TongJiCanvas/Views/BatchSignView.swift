import SwiftUI
import WebKit
import UIKit

// MARK: - Signing state

enum SignStatus {
    case signing, success, failure, expired
    var label: String {
        switch self {
        case .signing: "签到中"
        case .success: "签到成功"
        case .failure: "签到失败"
        case .expired: "认证过期"
        }
    }
    var color: Color {
        switch self {
        case .signing: Color(hex: 0x7C3AED)
        case .success: .green
        case .failure: .red
        case .expired: .orange
        }
    }
    var icon: String {
        switch self {
        case .signing: "arrow.clockwise"
        case .success: "checkmark.circle.fill"
        case .failure: "xmark.circle.fill"
        case .expired: "exclamationmark.triangle.fill"
        }
    }
}

// MARK: - Sign result

private struct SignResult {
    let html: String
    let status: SignStatus
}

// MARK: - ViewModel

@MainActor
final class BatchSignViewModel: ObservableObject {
    @Published var statuses: [UUID: SignStatus] = [:]
    @Published var expandedIds: Set<UUID> = []
    @Published private(set) var resultHTML: [UUID: String] = [:]
    @Published private(set) var allComplete = false
    @Published private(set) var errorSummary: String?

    private var sessions: [UserSession] = []
    let attendanceURL: URL

    private static let mobileUA =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/120.0.0.0 Mobile/15E148 Safari/604.1"

    static let urlSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 10
        config.httpMaximumConnectionsPerHost = 8
        config.httpAdditionalHeaders = [
            "User-Agent": mobileUA,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8"
        ]
        return URLSession(configuration: config)
    }()

    var hasActiveSigning: Bool { statuses.values.contains(.signing) }

    init(attendanceURL: URL) { self.attendanceURL = attendanceURL }

    func start(sessions: [UserSession]) {
        self.sessions = sessions
        allComplete = false
        errorSummary = nil
        sessions.forEach { statuses[$0.id] = .signing }
        Task { await signAll() }
    }

    func retry(session: UserSession) {
        statuses[session.id] = .signing
        resultHTML.removeValue(forKey: session.id)
        allComplete = false
        errorSummary = nil
        Task { await sign(session: session) }
    }

    func toggleExpanded(_ id: UUID) {
        if expandedIds.contains(id) { expandedIds.remove(id) } else { expandedIds.insert(id) }
    }

    // MARK: - Sign all

    private func signAll() async {
        await withTaskGroup(of: Void.self) { group in
            for session in sessions {
                group.addTask { [weak self] in await self?.sign(session: session) }
            }
        }
        // All tasks done — generate error summary if needed
        let failures = statuses.filter { $0.value == .failure || $0.value == .expired }
        if !failures.isEmpty {
            let expiredCount = failures.filter { $0.value == .expired }.count
            let failedCount = failures.count - expiredCount
            var parts: [String] = []
            if failedCount > 0 { parts.append("\(failedCount) 个签到失败") }
            if expiredCount > 0 { parts.append("\(expiredCount) 个认证过期，需要重新登录") }
            errorSummary = parts.joined(separator: "，")
        }
        allComplete = true
    }

    // MARK: - Sign single user

    private func sign(session: UserSession) async {
        let cookieValue = session.accessToken ?? ""

        let result = await Self.performSign(
            url: attendanceURL,
            cookieValue: cookieValue
        )

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(result.status == .success ? .success : .error)

        resultHTML[session.id] = result.html
        statuses[session.id] = result.status
    }

    /// Non-isolated network call — runs on cooperative thread pool, not main actor.
    /// All parameters are value types so no @MainActor crossing needed.
    private nonisolated static func performSign(
        url: URL,
        cookieValue: String
    ) async -> SignResult {
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 5
        )
        if !cookieValue.isEmpty {
            request.setValue(cookieValue, forHTTPHeaderField: "Cookie")
        }

        // First attempt
        let firstResult = await executeRequest(request)
        switch firstResult {
        case .success(let html):
            return evaluate(html: html)
        case .failure(let error):
            if shouldRetry(error) {
                // One automatic retry for transient errors
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s backoff
                let secondResult = await executeRequest(request)
                switch secondResult {
                case .success(let html):
                    return evaluate(html: html)
                case .failure:
                    return SignResult(
                        html: errorPlaceholder(error: error),
                        status: .failure
                    )
                }
            } else {
                return SignResult(
                    html: errorPlaceholder(error: error),
                    status: .failure
                )
            }
        }
    }

    private nonisolated static func executeRequest(_ request: URLRequest) async -> Result<String, Error> {
        do {
            let (data, response) = try await urlSession.data(for: request)
            let html = decodeHTML(data: data, response: response)
            return .success(html)
        } catch {
            return .failure(error)
        }
    }

    private nonisolated static func evaluate(html: String) -> SignResult {
        // Check for expired session (redirected to login)
        let lowerHTML = html.lowercased()
        let isExpired = lowerHTML.contains("统一身份认证")
            || lowerHTML.contains("oauth2/authorize")
            || lowerHTML.contains("openid_connect")
            || lowerHTML.contains("/login")

        if isExpired {
            return SignResult(html: html, status: .expired)
        }

        let success = html.contains("签到成功")
            || html.contains("已签过")
            || html.contains("签到已完成")
        return SignResult(html: html, status: success ? .success : .failure)
    }

    private nonisolated static func shouldRetry(_ error: Error) -> Bool {
        let code = (error as? URLError)?.code
        return code == .timedOut
            || code == .networkConnectionLost
            || code == .notConnectedToInternet
            || code == .dnsLookupFailed
            || code == .cannotFindHost
            || code == .cannotConnectToHost
    }

    // MARK: - HTML decode

    private nonisolated static func decodeHTML(data: Data, response: URLResponse) -> String {
        if let textEncodingName = response.textEncodingName {
            let cfEnc = CFStringConvertIANACharSetNameToEncoding(textEncodingName as CFString)
            if cfEnc != kCFStringEncodingInvalidId {
                let nsEnc = CFStringConvertEncodingToNSStringEncoding(cfEnc)
                if let s = String(data: data, encoding: String.Encoding(rawValue: nsEnc)), !s.isEmpty {
                    return s
                }
            }
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
    }

    private nonisolated static func errorPlaceholder(error: Error) -> String {
        """
        <!doctype html>
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>body{font-family:-apple-system;color:#dc2626;padding:24px;background:#fff;line-height:1.5}h3{margin-top:0}</style>
        </head><body>
        <h3>请求失败</h3>
        <p>\(error.localizedDescription)</p>
        </body></html>
        """
    }

    var successCount: Int { statuses.values.filter { $0 == .success }.count }
    var failureCount: Int { statuses.values.filter { $0 == .failure || $0 == .expired }.count }
    var progress: Double {
        guard !statuses.isEmpty else { return 0 }
        let done = statuses.values.filter { $0 != .signing }.count
        return Double(done) / Double(statuses.count)
    }
}

// MARK: - View

struct BatchSignView: View {
    let attendanceURL: URL
    let selectedIds: Set<UUID>

    @EnvironmentObject var repo: SessionRepository
    @Environment(\.dismiss) var dismiss
    @StateObject private var vm: BatchSignViewModel
    @State private var showBackConfirm = false

    init(attendanceURL: URL, selectedIds: Set<UUID>) {
        self.attendanceURL = attendanceURL
        self.selectedIds   = selectedIds
        _vm = StateObject(wrappedValue: BatchSignViewModel(attendanceURL: attendanceURL))
    }

    private var selectedSessions: [UserSession] {
        repo.sessions.filter { selectedIds.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                summaryCard

                if let summary = vm.errorSummary, vm.allComplete {
                    errorSummaryCard(summary)
                }

                ForEach(selectedSessions) { session in
                    sessionCard(session)
                }
            }
            .padding(16)
        }
        .navigationTitle("批量签到")
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(vm.hasActiveSigning)
        .interactiveDismissDisabled(vm.hasActiveSigning)
        .toolbar {
            if vm.hasActiveSigning {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("返回") { showBackConfirm = true }
                }
            }
        }
        .alert("签到仍在进行中", isPresented: $showBackConfirm) {
            Button("继续等待", role: .cancel) {}
            Button("放弃并返回", role: .destructive) { dismiss() }
        } message: {
            Text("还有 \(vm.statuses.values.filter { $0 == .signing }.count) 个账号正在签到，返回将丢失当前进度。")
        }
        .onAppear { vm.start(sessions: selectedSessions) }
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("签到进度").font(.headline)

            ProgressView(value: vm.progress)
                .tint(vm.progress >= 1.0 ? .green : Color(hex: 0x7C3AED))

            HStack(spacing: 20) {
                Text("总计 \(selectedSessions.count)").font(.subheadline)
                Text("成功 \(vm.successCount)").font(.subheadline).foregroundStyle(.green)
                if vm.failureCount > 0 {
                    Text("失败 \(vm.failureCount)").font(.subheadline).foregroundStyle(.red)
                }
            }

            Label(attendanceURL.absoluteString, systemImage: "link")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func errorSummaryCard(_ summary: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(summary)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Per-user card

    @ViewBuilder
    private func sessionCard(_ session: UserSession) -> some View {
        let status = vm.statuses[session.id] ?? .signing
        let expanded = vm.expandedIds.contains(session.id)
        let hasResult = vm.resultHTML[session.id] != nil

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayName).font(.headline)
                    Text(session.hasCredentials ? "已保存认证信息" : "未保存认证信息")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge(status)
            }

            if status == .signing {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 4)
            }

            HStack(spacing: 12) {
                if hasResult {
                    Button { vm.toggleExpanded(session.id) } label: {
                        Label(expanded ? "收起" : "查看响应",
                              systemImage: expanded ? "chevron.up" : "eye")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                if status == .failure || status == .expired {
                    Button { vm.retry(session: session) } label: {
                        Label("重试", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }

            if expanded, let html = vm.resultHTML[session.id] {
                ResultWebView(html: html, baseURL: attendanceURL)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else if expanded {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.tertiarySystemBackground))
                    VStack(spacing: 8) {
                        ProgressView()
                        Text(status == .signing ? "签到进行中..." : "加载中...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 120)
            }
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: expanded)
    }

    private func statusBadge(_ status: SignStatus) -> some View {
        Label(status.label, systemImage: status.icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(status.color)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(status.color.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Result WebView (renders Canvas response HTML with full CSS/iframe support)

private struct ResultWebView: UIViewRepresentable {
    let html: String
    let baseURL: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.backgroundColor = .clear
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            uiView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    final class Coordinator {
        var lastHTML: String?
    }
}
