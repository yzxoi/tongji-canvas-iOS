import SwiftUI

// MARK: - Color scheme mode

enum ColorSchemeMode: Int {
    case system = 0, light, dark
    var label: String {
        switch self {
        case .system: "System"
        case .light:  "Light"
        case .dark:   "Dark"
        }
    }
    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light:  "sun.max.fill"
        case .dark:   "moon.fill"
        }
    }
}

struct MainView: View {
    @EnvironmentObject var repo: SessionRepository
    @AppStorage("colorSchemeMode") private var schemeMode: Int = ColorSchemeMode.system.rawValue

    @State private var selectedIds: Set<UUID> = []
    @State private var showAddSheet        = false
    @State private var showOAuthLogin      = false
    @State private var showManualAdd       = false
    @State private var showScanner         = false
    @State private var attendanceURL: AttendanceLink? = nil

    // Group state
    @State private var allUsersExpanded = true
    @State private var showAddGroup     = false
    @State private var showAbout        = false

    // Edit
    @State private var editingSession: UserSession? = nil
    @State private var editingGroup:   Course?      = nil

    // Toast
    @State private var toastMessage: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil

    var body: some View {
        NavigationStack {
            listContent
                .navigationTitle("Session Mux")
                .toolbar { toolbarItems }
                .safeAreaInset(edge: .bottom) {
                    floatingDock
                        .padding(EdgeInsets(top: 0, leading: 12, bottom: 4, trailing: 12))
                }
                .navigationDestination(item: $attendanceURL) { link in
                    BatchSignView(
                        attendanceURL: link.url,
                        selectedIds: selectedIds
                    )
                }
        }
        .preferredColorScheme(colorScheme)
        .onAppear { selectedIds = repo.selectedIds }
        .onChange(of: selectedIds) { _, new in repo.selectedIds = new }
        .sheet(isPresented: $showOAuthLogin) {
            LoginView { repo.selectedIds = selectedIds }
        }
        .sheet(isPresented: $showManualAdd) {
            ManualAddView()
        }
        .sheet(item: $editingSession) { s in
            EditSessionView(session: s)
        }
        .sheet(item: $editingGroup) { g in
            EditCourseView(course: g)
        }
        .sheet(isPresented: $showAddGroup) {
            AddCourseView()
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
        .fullScreenCover(isPresented: $showScanner) {
            ScannerView { url in
                showScanner = false
                attendanceURL = AttendanceLink(url: url)
            }
        }
        .overlay(toastOverlay)
    }

    // MARK: - List content

    private var listContent: some View {
        List {
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
                    title: "Identities", count: repo.sessions.count,
                    icon: "person.2", color: Color(hex: 0x7C3AED),
                    expanded: allUsersExpanded
                ) { allUsersExpanded.toggle() }
            }

            ForEach(repo.courses) { course in
                let members = repo.sessions.filter { course.memberIds.contains($0.id) }
                Section {
                } header: {
                    CourseGroupHeader(
                        course: course,
                        memberCount: members.count,
                        allSelected: members.allSatisfy { selectedIds.contains($0.id) },
                        onTap: { editingGroup = course },
                        onToggleAll: {
                            let all = members.allSatisfy { selectedIds.contains($0.id) }
                            if all { members.forEach { selectedIds.remove($0.id) } }
                            else   { members.forEach { selectedIds.insert($0.id) } }
                        }
                    )
                }
            }

            Section {
                Button {
                    showAddGroup = true
                } label: {
                    Label("New Group", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(Color(hex: 0x7C3AED))
                }
                .listRowBackground(Color(hex: 0x7C3AED).opacity(0.08))
            }
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
        HStack(spacing: 10) {
            Button {
                showAddSheet = true
            } label: {
                Label("Add Identity", systemImage: "plus")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(Color(.label))
            }
            .buttonStyle(.plain)

            let canFanOut = !selectedIds.isEmpty
            Button {
                guard canFanOut else { return }
                showScanner = true
            } label: {
                Label(
                    selectedIds.isEmpty ? "Fan-out" : "Fan-out (\(selectedIds.count))",
                    systemImage: "point.3.connected.trianglepath.dotted"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    canFanOut
                    ? LinearGradient(
                        colors: [Color(hex: 0x7C3AED), Color(hex: 0x9333EA)],
                        startPoint: .leading, endPoint: .trailing
                    )
                    : LinearGradient(
                        colors: [Color(.systemFill), Color(.systemFill)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(canFanOut ? .white : Color(.secondaryLabel))
            }
            .disabled(!canFanOut)
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .confirmationDialog("Add Identity", isPresented: $showAddSheet) {
            Button("Sign in via IAM (auto-capture)") { showOAuthLogin = true }
            Button("Paste Credential") { showManualAdd = true }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Color scheme

    private var colorScheme: ColorScheme? {
        switch ColorSchemeMode(rawValue: schemeMode) ?? .system {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Menu {
                    ForEach([ColorSchemeMode.system, .light, .dark], id: \.rawValue) { mode in
                        Button {
                            schemeMode = mode.rawValue
                        } label: {
                            Label(mode.label, systemImage: mode.icon)
                        }
                    }
                } label: {
                    let current = ColorSchemeMode(rawValue: schemeMode) ?? .system
                    Label("Theme: \(current.label)", systemImage: current.icon)
                }
                Divider()
                Button { showAbout = true } label: {
                    Label("About", systemImage: "info.circle")
                }
                Divider()
                Button(action: importFromClipboard) {
                    Label("Import from Clipboard", systemImage: "doc.on.clipboard")
                }
                Button(action: exportToClipboard) {
                    Label("Export to Clipboard", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Import / Export

    private func importFromClipboard() {
        guard let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { showToast("Clipboard is empty"); return }
        do {
            let (u, c) = try repo.importJSON(text)
            showToast("Imported \(u) identities" + (c > 0 ? ", \(c) groups" : ""))
        } catch {
            showToast("Invalid clipboard format")
        }
    }

    private func exportToClipboard() {
        guard !repo.sessions.isEmpty else { showToast("No identities to export"); return }
        UIPasteboard.general.string = repo.exportJSON()
        showToast("Exported \(repo.sessions.count) identities")
    }

    // MARK: - Toast

    private func showToast(_ msg: String) {
        toastTask?.cancel()
        toastMessage = msg
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            toastMessage = nil
        }
    }

    @ViewBuilder
    private var toastOverlay: some View {
        // The ZStack is always present so the dismiss transition can animate out.
        ZStack(alignment: .bottom) {
            Color.clear
            if let msg = toastMessage {
                Text(msg)
                    .font(.subheadline)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(.regularMaterial)
                    .clipShape(Capsule())
                    .shadow(radius: 4)
                    .padding(.bottom, 120)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toastMessage)
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

// MARK: - Identifiable wrapper

struct AttendanceLink: Identifiable, Hashable {
    let id = UUID()
    let url: URL
}
