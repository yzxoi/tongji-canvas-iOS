import SwiftUI

struct MainView: View {
    @EnvironmentObject var repo: SessionRepository

    // Selection
    @State private var selectedIds: Set<UUID> = []

    // Navigation
    @State private var showAddSheet        = false
    @State private var showOAuthLogin      = false
    @State private var showManualAdd       = false
    @State private var showScanner         = false
    @State private var attendanceURL: URL? = nil

    // Course state
    @State private var allUsersExpanded = true
    @State private var showAddCourse    = false

    // Edit
    @State private var editingSession: UserSession? = nil
    @State private var editingCourse:  Course?      = nil

    // Snackbar
    @State private var toastMessage: String? = nil

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                listContent
                    .navigationTitle("批量签到")
                    .toolbar { toolbarItems }
                floatingDock
            }
        }
        .onAppear { selectedIds = repo.selectedIds }
        .onChange(of: selectedIds) { _, new in repo.selectedIds = new }
        // Sheets & navigation
        .sheet(isPresented: $showOAuthLogin) {
            LoginView { repo.selectedIds = selectedIds }
        }
        .sheet(isPresented: $showManualAdd) {
            ManualAddView()
        }
        .sheet(item: $editingSession) { s in
            EditSessionView(session: s)
        }
        .sheet(item: $editingCourse) { c in
            EditCourseView(course: c)
        }
        .sheet(isPresented: $showAddCourse) {
            AddCourseView()
        }
        .fullScreenCover(isPresented: $showScanner) {
            ScannerView { url in
                attendanceURL = url
                showScanner   = false
            }
        }
        .navigationDestination(item: $attendanceURL) { url in
            BatchSignView(
                attendanceURL: url,
                selectedIds: selectedIds
            )
        }
        .overlay(toastOverlay)
    }

    // MARK: - List content

    private var listContent: some View {
        List {
            // ── All users section ─────────────────────────────
            Section {
                if allUsersExpanded {
                    ForEach(repo.sessions) { session in
                        SessionCard(
                            session: session,
                            isSelected: Binding(
                                get:  { selectedIds.contains(session.id) },
                                set:  { if $0 { selectedIds.insert(session.id) } else { selectedIds.remove(session.id) } }
                            ),
                            onEdit:   { editingSession = session },
                            onDelete: { repo.remove(sessionId: session.id); selectedIds.remove(session.id) }
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color(.systemGroupedBackground))
                    }
                }
            } header: {
                groupHeader(
                    title: "全部人员", count: repo.sessions.count,
                    icon: "person.2", color: Color(hex: 0x7C3AED),
                    expanded: allUsersExpanded
                ) { allUsersExpanded.toggle() }
            }

            // ── Course sections ───────────────────────────────
            ForEach(repo.courses) { course in
                let members = repo.sessions.filter { course.memberIds.contains($0.id) }
                Section {
                    // No rows shown inside courses (not expanded list, just header with select-all)
                } header: {
                    CourseGroupHeader(
                        course: course,
                        memberCount: members.count,
                        allSelected: members.allSatisfy { selectedIds.contains($0.id) },
                        onTap: { editingCourse = course },
                        onToggleAll: {
                            let all = members.allSatisfy { selectedIds.contains($0.id) }
                            if all { members.forEach { selectedIds.remove($0.id) } }
                            else   { members.forEach { selectedIds.insert($0.id) } }
                        }
                    )
                }
            }

            // ── Add course button ─────────────────────────────
            Section {
                Button {
                    showAddCourse = true
                } label: {
                    Label("新建课程分组", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(Color(hex: 0x7C3AED))
                }
                .listRowBackground(Color(hex: 0xF0F0FF))
            }

            // Bottom spacer so the dock doesn't cover content
            Section { Color.clear.frame(height: 80) }
                .listRowBackground(Color(.systemGroupedBackground))
                .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.visible)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Group header

    private func groupHeader(
        title: String, count: Int, icon: String, color: Color,
        expanded: Bool, onToggle: @escaping () -> Void
    ) -> some View {
        Button(action: onToggle) {
            HStack {
                Image(systemName: icon).foregroundStyle(color)
                Text(title).foregroundStyle(color).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(count)").font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 2)
                    .background(color.opacity(0.15)).clipShape(Capsule())
                    .foregroundStyle(color)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(color).font(.caption)
            }
        }
        .buttonStyle(.plain)
        .textCase(nil)
    }

    // MARK: - Floating dock

    private var floatingDock: some View {
        HStack(spacing: 12) {
            Button {
                showAddSheet = true
            } label: {
                Label("添加账号", systemImage: "plus")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .foregroundStyle(Color(.label))
            }

            let canSign = !selectedIds.isEmpty
            Button {
                guard canSign else { return }
                showScanner = true
            } label: {
                HStack {
                    Image(systemName: "qrcode.viewfinder")
                    Text(selectedIds.isEmpty ? "一键签到" : "一键签到（\(selectedIds.count)）")
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: canSign ? [Color(hex: 0x7C3AED), Color(hex: 0x9333EA)] : [Color(.systemFill), Color(.systemFill)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .foregroundStyle(canSign ? .white : Color(.secondaryLabel))
            }
            .disabled(!canSign)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: 32)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        // Add-account action sheet
        .confirmationDialog("添加账号", isPresented: $showAddSheet) {
            Button("在线登录添加（自动捕获 Cookies）") { showOAuthLogin = true }
            Button("手动录入 Cookies") { showManualAdd = true }
            Button("取消", role: .cancel) {}
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button(action: importFromClipboard) {
                    Label("从剪贴板导入", systemImage: "doc.on.clipboard")
                }
                Button(action: exportToClipboard) {
                    Label("导出到剪贴板", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Import / Export

    private func importFromClipboard() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { showToast("剪贴板为空"); return }
        do {
            let (u, c) = try repo.importJSON(text)
            showToast("已导入 \(u) 个账号" + (c > 0 ? "、\(c) 个课程" : ""))
        } catch {
            showToast("剪贴板内容格式有误")
        }
    }

    private func exportToClipboard() {
        guard !repo.sessions.isEmpty else { showToast("暂无可导出的账号"); return }
        UIPasteboard.general.string = repo.exportJSON()
        showToast("已导出 \(repo.sessions.count) 个账号")
    }

    // MARK: - Toast

    private func showToast(_ msg: String) {
        toastMessage = msg
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { toastMessage = nil }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        if let msg = toastMessage {
            VStack {
                Spacer()
                Text(msg)
                    .font(.subheadline)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
                    .shadow(radius: 4)
                    .padding(.bottom, 120)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .animation(.spring(), value: toastMessage)
        }
    }
}

// MARK: - Course group header component

private struct CourseGroupHeader: View {
    let course: Course
    let memberCount: Int
    let allSelected: Bool
    let onTap: () -> Void
    let onToggleAll: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "folder").foregroundStyle(Color(hex: 0x0EA5E9))
            Text(course.name)
                .foregroundStyle(Color(hex: 0x0EA5E9))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer()
            Text("\(memberCount)").font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 2)
                .background(Color(hex: 0x0EA5E9).opacity(0.15)).clipShape(Capsule())
                .foregroundStyle(Color(hex: 0x0EA5E9))
            if memberCount > 0 {
                Button(action: onToggleAll) {
                    Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(Color(hex: 0x0EA5E9))
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .textCase(nil)
    }
}
