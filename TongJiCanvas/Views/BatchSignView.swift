import SwiftUI
import WebKit

// MARK: - Signing state

enum SignStatus {
    case pending, signing, success, failure
    var label: String {
        switch self { case .pending: "等待中"; case .signing: "签到中"; case .success: "签到成功"; case .failure: "签到失败" }
    }
    var color: Color {
        switch self { case .pending: .secondary; case .signing: Color(hex: 0x7C3AED); case .success: .green; case .failure: .red }
    }
    var icon: String {
        switch self { case .pending: "clock"; case .signing: "arrow.clockwise"; case .success: "checkmark.circle.fill"; case .failure: "xmark.circle.fill" }
    }
}

// MARK: - ViewModel

@MainActor
final class BatchSignViewModel: ObservableObject {
    @Published var statuses: [UUID: SignStatus] = [:]

    private var sessions: [UserSession] = []
    private var signers: [UUID: SigningWebView] = [:]
    var attendanceURL: URL

    init(attendanceURL: URL) { self.attendanceURL = attendanceURL }

    func start(sessions: [UserSession]) {
        self.sessions = sessions
        sessions.forEach { statuses[$0.id] = .pending }
        Task { await signAll() }
    }

    func retry(session: UserSession) {
        statuses[session.id] = .pending
        Task { await sign(session: session) }
    }

    private func signAll() async {
        var tasks: [Task<Void, Never>] = []
        for session in sessions {
            tasks.append(Task { await sign(session: session) })
        }
        for task in tasks { await task.value }
    }

    private func sign(session: UserSession) async {
        statuses[session.id] = .signing

        // Build isolated data store + inject cookies
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let cookies = CookieHelper.parseCookies(from: session.accessToken ?? "")
        await CookieHelper.inject(cookies: cookies, into: dataStore)

        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore

        // Use our actor-isolated signing helper
        let signer = SigningWebView(configuration: config)
        signers[session.id] = signer

        let ok = await signer.sign(url: attendanceURL)
        statuses[session.id] = ok ? .success : .failure
    }

    var successCount: Int { statuses.values.filter { $0 == .success }.count }
    var failureCount: Int { statuses.values.filter { $0 == .failure }.count }
    var progress: Double {
        guard !statuses.isEmpty else { return 0 }
        let done = statuses.values.filter { $0 == .success || $0 == .failure }.count
        return Double(done) / Double(statuses.count)
    }
}

// MARK: - View

struct BatchSignView: View {
    let attendanceURL: URL
    let selectedIds: Set<UUID>

    @EnvironmentObject var repo: SessionRepository
    @StateObject private var vm: BatchSignViewModel

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
                ForEach(selectedSessions) { session in
                    sessionCard(session)
                }
            }
            .padding(16)
        }
        .navigationTitle("批量签到")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { vm.start(sessions: selectedSessions) }
    }

    // MARK: - Summary card

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("签到进度").font(.headline)

            ProgressView(value: vm.progress)
                .tint(Color(hex: 0x7C3AED))

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

    // MARK: - Per-user card

    @ViewBuilder
    private func sessionCard(_ session: UserSession) -> some View {
        let status = vm.statuses[session.id] ?? .pending
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
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }

            if status == .failure {
                Button {
                    vm.retry(session: session)
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
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
