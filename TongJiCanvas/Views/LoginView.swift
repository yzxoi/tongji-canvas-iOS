import SwiftUI
import WebKit
import Combine

// MARK: - ViewModel

@MainActor
final class LoginViewModel: NSObject, ObservableObject {
    @Published var currentURL    = ""
    @Published var loginDetected = false
    @Published var countdown     = 0
    @Published var isMobileUA    = true
    @Published var statusMessage = "请在下方统一认证页面完成登录，系统会自动捕获 Cookies。"

    let loginURL = URL(string: "https://canvas.tongji.edu.cn/lms/mobile/forscan?courseCode=2333&rollCallToken=2333")!

    var webView: WKWebView?
    var onSaved: () -> Void = {}
    var repo: SessionRepository?

    private var countdownTask: Task<Void, Never>?
    /// 跟踪是否已经离开过 Canvas 域（跳转到 IAM 登录页）。
    /// 只有先经过 IAM 再回到 Canvas，才能判定登录成功，
    /// 避免初始 URL 加载时误触发。
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

    /// 等 cookie 全部清完后再加载，避免竞态条件。
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

    /// 由导航代理每次 URL 变化时调用（与 Android 版逻辑对齐）。
    func handleURLChange(_ url: URL) {
        currentURL = url.absoluteString
        let s = url.absoluteString

        let isCanvas   = s.hasPrefix("https://canvas.tongji.edu.cn/")
        let isAuthPage = s.contains("login") || s.contains("oauth2") ||
                         s.contains("openid_connect") || s.contains("saml")

        // 只要 URL 不是"Canvas 正常页"，就记录已访问过非 Canvas 页面
        if !isCanvas || isAuthPage {
            hasVisitedNonCanvas = true
        }

        // 登录成功的充要条件：
        //   1. 落地在 Canvas 正常页（非认证流程 URL）
        //   2. 之前已经离开过 Canvas（说明经历了 IAM 登录跳转）
        if isCanvas && !isAuthPage && hasVisitedNonCanvas && !loginDetected {
            loginDetected = true
            startCountdown()
        }
    }

    private func startCountdown() {
        statusMessage = ""
        countdownTask = Task { @MainActor in
            for i in stride(from: 5, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                countdown = i
                statusMessage = "登录成功！系统将在 \(i) 秒后自动提取认证信息。"
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            countdown = 0
            statusMessage = "正在提取认证信息..."
            await extractAndSave()
        }
    }

    private func extractAndSave() async {
        guard let wv = webView, let repo = repo else { return }
        let cookieString = await CookieHelper.captureCanvasCookies(
            from: wv.configuration.websiteDataStore.httpCookieStore
        )
        guard !cookieString.isEmpty else {
            statusMessage = "未找到认证信息，请重试。"
            loginDetected = false
            hasVisitedNonCanvas = false
            return
        }
        let displayName = "用户\(Int(Date().timeIntervalSince1970))"
        repo.addOrUpdate(displayName: displayName, accessToken: cookieString)
        onSaved()
    }
}

// MARK: - View

struct LoginView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var repo: SessionRepository
    @StateObject private var vm = LoginViewModel()

    var onSaved: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Tips card
                tipCard

                // UA switcher
                Picker("模式", selection: Binding(get: { vm.isMobileUA }, set: { vm.switchUA(toMobile: $0) })) {
                    Label("移动端", systemImage: "iphone").tag(true)
                    Label("桌面端", systemImage: "desktopcomputer").tag(false)
                }
                .pickerStyle(.segmented)

                // Status chips
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

                // WebView
                LoginWebViewWrapper(vm: vm)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        vm.loginDetected ? nil :
                        LinearProgressIndicator().padding(.top, -2),
                        alignment: .top
                    )

                // Status text
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

private struct LinearProgressIndicator: UIViewRepresentable {
    func makeUIView(context: Context) -> UIProgressView {
        let pv = UIProgressView(progressViewStyle: .bar)
        pv.isIndeterminate = true
        return pv
    }
    func updateUIView(_ uiView: UIProgressView, context: Context) {}
}

extension UIProgressView {
    var isIndeterminate: Bool {
        get { false }
        set {
            if newValue {
                let anim = CABasicAnimation(keyPath: "position.x")
                anim.fromValue = -bounds.width
                anim.toValue   = bounds.width * 2
                anim.duration  = 1.0
                anim.repeatCount = .infinity
                layer.add(anim, forKey: "shimmer")
                progress = 0.4
            }
        }
    }
}

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

// MARK: - Manual Add Sheet

struct ManualAddView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var repo: SessionRepository

    @State private var displayName = ""
    @State private var accessToken = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("用户信息") {
                    TextField("用户昵称", text: $displayName)
                    TextEditor(text: $accessToken)
                        .frame(minHeight: 100)
                        .overlay(
                            Group {
                                if accessToken.isEmpty {
                                    Text("认证信息 (Cookies)")
                                        .foregroundStyle(.tertiary)
                                        .padding(4)
                                        .allowsHitTesting(false)
                                }
                            }, alignment: .topLeading
                        )
                }
            }
            .navigationTitle("手动录入 Cookies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("添加") {
                        guard !displayName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        repo.addOrUpdate(displayName: displayName, accessToken: accessToken.isEmpty ? nil : accessToken)
                        dismiss()
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Edit Session Sheet

struct EditSessionView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var repo: SessionRepository

    let session: UserSession
    @State private var displayName: String
    @State private var accessToken: String
    @State private var selectedCourseIds: Set<UUID>

    init(session: UserSession) {
        self.session = session
        _displayName = State(initialValue: session.displayName)
        _accessToken = State(initialValue: session.accessToken ?? "")
        _selectedCourseIds = State(initialValue: [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("用户信息") {
                    TextField("用户昵称", text: $displayName)
                    TextEditor(text: $accessToken)
                        .frame(minHeight: 100)
                }
                if !repo.courses.isEmpty {
                    Section("所属课程") {
                        ForEach(repo.courses) { course in
                            Toggle(course.name, isOn: Binding(
                                get: { selectedCourseIds.contains(course.id) },
                                set: { if $0 { selectedCourseIds.insert(course.id) } else { selectedCourseIds.remove(course.id) } }
                            ))
                        }
                    }
                }
            }
            .navigationTitle("编辑用户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        var updated = session
                        updated.displayName = displayName
                        updated.accessToken = accessToken.isEmpty ? nil : accessToken
                        repo.update(updated)
                        // Update course memberships
                        for i in repo.courses.indices {
                            let cid = repo.courses[i].id
                            var course = repo.courses[i]
                            if selectedCourseIds.contains(cid) {
                                if !course.memberIds.contains(session.id) { course.memberIds.append(session.id) }
                            } else {
                                course.memberIds.removeAll { $0 == session.id }
                            }
                            repo.update(course)
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                selectedCourseIds = Set(repo.courses.filter { $0.memberIds.contains(session.id) }.map(\.id))
            }
        }
    }
}

// MARK: - Add Course Sheet

struct AddCourseView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var repo: SessionRepository

    @State private var courseName = ""
    @State private var selectedMemberIds: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("课程名称", text: $courseName) }
                if !repo.sessions.isEmpty {
                    Section("选择成员") {
                        ForEach(repo.sessions) { s in
                            Toggle(s.displayName, isOn: Binding(
                                get: { selectedMemberIds.contains(s.id) },
                                set: { if $0 { selectedMemberIds.insert(s.id) } else { selectedMemberIds.remove(s.id) } }
                            ))
                        }
                    }
                }
            }
            .navigationTitle("新建课程分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("创建") {
                        guard !courseName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        var c = repo.addCourse(name: courseName)
                        c.memberIds = Array(selectedMemberIds)
                        repo.update(c)
                        dismiss()
                    }
                    .disabled(courseName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Edit Course Sheet

struct EditCourseView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var repo: SessionRepository

    let course: Course
    @State private var courseName: String
    @State private var memberIds: Set<UUID>

    init(course: Course) {
        self.course = course
        _courseName = State(initialValue: course.name)
        _memberIds  = State(initialValue: Set(course.memberIds))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("课程名称", text: $courseName) }
                Section("成员") {
                    ForEach(repo.sessions) { s in
                        Toggle(s.displayName, isOn: Binding(
                            get: { memberIds.contains(s.id) },
                            set: { if $0 { memberIds.insert(s.id) } else { memberIds.remove(s.id) } }
                        ))
                    }
                }
                Section {
                    Button("删除课程", role: .destructive) {
                        repo.remove(courseId: course.id)
                        dismiss()
                    }
                }
            }
            .navigationTitle("编辑课程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") {
                        var updated = course
                        updated.name = courseName
                        updated.memberIds = Array(memberIds)
                        repo.update(updated)
                        dismiss()
                    }
                }
            }
        }
    }
}
