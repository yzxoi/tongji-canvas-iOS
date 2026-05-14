import SwiftUI
import WebKit
import UIKit

// MARK: - Request status

enum SignStatus {
    case signing, success, failure, expired
    var label: String {
        switch self {
        case .signing: "Pending"
        case .success: "OK"
        case .failure: "Failed"
        case .expired: "Expired"
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
        let failures = statuses.filter { $0.value == .failure || $0.value == .expired }
        if !failures.isEmpty {
            let expiredCount = failures.filter { $0.value == .expired }.count
            let failedCount = failures.count - expiredCount
            var parts: [String] = []
            if failedCount > 0 { parts.append("\(failedCount) failed") }
            if expiredCount > 0 { parts.append("\(expiredCount) expired, re-authentication required") }
            errorSummary = parts.joined(separator: ", ")
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

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(result.status == .success ? .success : .error)

        resultHTML[session.id] = result.html
        statuses[session.id] = result.status
    }

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

        let firstResult = await executeRequest(request)
        switch firstResult {
        case .success(let html):
            return evaluate(html: html)
        case .failure(let error):
            if shouldRetry(error) {
                try? await Task.sleep(nanoseconds: 500_000_000)
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
        // Detect session expiry (redirected to IAM login)
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
        <h3>Request Failed</h3>
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
        .navigationTitle("Multiplexer")
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(vm.hasActiveSigning)
        .interactiveDismissDisabled(vm.hasActiveSigning)
        .toolbar {
            if vm.hasActiveSigning {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") { showBackConfirm = true }
                }
            }
        }
        .alert("Requests in Flight", isPresented: $showBackConfirm) {
            Button("Wait", role: .cancel) {}
            Button("Abort", role: .destructive) { dismiss() }
        } message: {
            Text("\(vm.statuses.values.filter { $0 == .signing }.count) request(s) still pending. Leaving will discard in-flight state.")
        }
        .onAppear { vm.start(sessions: selectedSessions) }
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        let isComplete = vm.progress >= 1.0
        let total      = selectedSessions.count
        return VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .center, spacing: Spacing.lg) {
                progressRing(isComplete: isComplete)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(isComplete ? "Fan-out Complete" : "Fan-out in Progress")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(Int(vm.progress * 100))% · \(total - vm.successCount - vm.failureCount) pending")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
            }

            HStack(spacing: Spacing.sm) {
                statTile(label: "Total", value: total, color: .secondary)
                statTile(label: "OK", value: vm.successCount, color: .green)
                statTile(label: "Fail", value: vm.failureCount, color: vm.failureCount > 0 ? .red : .secondary)
            }

            Label(attendanceURL.absoluteString, systemImage: "link")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: Radius.inner))
        }
        .padding(Spacing.xl)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }

    /// Circular progress ring; turns green at completion.
    private func progressRing(isComplete: Bool) -> some View {
        let ringColor: Color = isComplete ? .green : Palette.accent
        return ZStack {
            Circle()
                .stroke(ringColor.opacity(0.15), lineWidth: 8)
            Circle()
                .trim(from: 0, to: max(vm.progress, 0.001))
                .stroke(ringColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: vm.progress)
            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Text("\(Int(vm.progress * 100))")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: 60, height: 60)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isComplete)
    }

    private func statTile(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.md - 2)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: Radius.inner))
    }

    private func errorSummaryCard(_ summary: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(summary)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.lg)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: Radius.inner))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.inner)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Per-identity card

    @ViewBuilder
    private func sessionCard(_ session: UserSession) -> some View {
        let status = vm.statuses[session.id] ?? .signing
        let expanded = vm.expandedIds.contains(session.id)
        let hasResult = vm.resultHTML[session.id] != nil

        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.md) {
                statusIcon(status)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(session.hasCredentials ? "Credential stored" : "No credential")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusBadge(status)
            }

            if status == .signing {
                LinearProgressBar()
            }

            HStack(spacing: Spacing.sm) {
                if hasResult {
                    Button { vm.toggleExpanded(session.id) } label: {
                        Label(expanded ? "Collapse" : "Inspect",
                              systemImage: expanded ? "chevron.up" : "eye")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(Palette.accent)
                }

                if status == .failure || status == .expired {
                    Button { vm.retry(session: session) } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(status.color)
                }
            }

            if expanded, let html = vm.resultHTML[session.id] {
                ResultWebView(html: html, baseURL: attendanceURL)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.inner))
            } else if expanded {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.inner)
                        .fill(Color(.tertiarySystemBackground))
                    VStack(spacing: Spacing.sm) {
                        ProgressView()
                        Text(status == .signing ? "Request in flight..." : "Loading...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 120)
            }
        }
        .padding(Spacing.xl)
        .background(Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(status.color.opacity(status == .signing ? 0.0 : 0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: expanded)
    }

    private func statusIcon(_ status: SignStatus) -> some View {
        ZStack {
            Circle()
                .fill(status.color.opacity(0.15))
                .frame(width: 36, height: 36)
            Image(systemName: status.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(status.color)
                .symbolEffect(.pulse, options: .repeating, value: status == .signing)
        }
    }

    private func statusBadge(_ status: SignStatus) -> some View {
        Text(status.label)
            .font(.caption.weight(.bold))
            .foregroundStyle(status.color)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 5)
            .background(status.color.opacity(0.12), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(status.color.opacity(0.25), lineWidth: 0.5)
            )
    }
}

// MARK: - Linear progress bar (indeterminate, on-brand)

private struct LinearProgressBar: View {
    @State private var offset: CGFloat = -1
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.accent.opacity(0.10))
                Capsule()
                    .fill(Palette.accentGradient)
                    .frame(width: geo.size.width * 0.4)
                    .offset(x: offset * geo.size.width)
            }
        }
        .frame(height: 4)
        .clipShape(Capsule())
        .onAppear {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                offset = 1
            }
        }
    }
}

// MARK: - Result WebView

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
