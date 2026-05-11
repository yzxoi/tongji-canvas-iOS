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
    // Export
    @State private var showExportSheet = false

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
        .sheet(isPresented: $showExportSheet) {
            ExportSheet(
                count: selectedIds.intersection(Set(repo.sessions.map(\.id))).count,
                onExport: { format in
                    showExportSheet = false
                    exportToClipboard(format: format, selectedIds: selectedIds)
                }
            )
            .presentationDetents([.medium])
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
                        allSelected: {
                            let memberIds = Set(members.map(\.id))
                            return !memberIds.isEmpty && selectedIds == memberIds
                        }(),
                        onTap: { editingGroup = course },
                        onToggleAll: {
                            let memberIds = Set(members.map(\.id))
                            if memberIds.isEmpty { return }
                            selectedIds = (selectedIds == memberIds) ? [] : memberIds
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
                Button {
                    showExportSheet = true
                } label: {
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

    private func exportToClipboard(format: SessionRepository.ExportFormat, selectedIds: Set<UUID>) {
        let count = selectedIds.intersection(Set(repo.sessions.map(\.id))).count
        guard count > 0 else { showToast("No identities selected"); return }
        let content = repo.exportJSON(format: format, selectedIds: selectedIds)
        guard !content.isEmpty else { return }
        UIPasteboard.general.string = content
        switch format {
        case .fullJSON:
            showToast("Exported \(count) identities (full)")
        case .rawCookies:
            showToast("Exported \(count) cookies (raw)")
        }
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

// MARK: - Export Sheet

struct ExportSheet: View {
    let count: Int
    let onExport: (SessionRepository.ExportFormat) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("\(count) identit" + (count == 1 ? "y" : "ies") + " selected")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    exportOption(
                        format: .fullJSON,
                        icon: "doc.richtext",
                        title: "Full JSON (Recommended)",
                        subtitle: "With display names & groups — works on both iOS & Android"
                    )

                    exportOption(
                        format: .rawCookies,
                        icon: "text.alignleft",
                        title: "Raw Cookies",
                        subtitle: "One cookie per line — for sharing credentials only"
                    )
                }
                .padding(.horizontal, 20)

                Spacer()
            }
            .padding(.top, 24)
            .navigationTitle("Export to Clipboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func exportOption(format: SessionRepository.ExportFormat,
                              icon: String, title: String, subtitle: String) -> some View {
        Button {
            onExport(format)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 36)
                    .foregroundStyle(Color(hex: 0xB8A2FF))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
