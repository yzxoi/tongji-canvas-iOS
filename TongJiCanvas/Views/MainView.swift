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

    @ViewBuilder
    private var listContent: some View {
        if repo.sessions.isEmpty && repo.courses.isEmpty {
            emptyState
        } else {
            sessionList
        }
    }

    private var sessionList: some View {
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
                    icon: "person.2.fill", color: Palette.accent,
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
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: "folder.badge.plus")
                            .font(.subheadline.weight(.semibold))
                        Text("New Group")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .opacity(0.6)
                    }
                    .foregroundStyle(Palette.accent)
                    .padding(.vertical, Spacing.xs)
                }
                .listRowBackground(Palette.accent.opacity(0.06))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.visible)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Empty state (no identities yet)

    private var emptyState: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Palette.accent.opacity(0.10))
                    .frame(width: 120, height: 120)
                Image(systemName: "person.2.fill")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(Palette.heroGradient)
            }

            VStack(spacing: Spacing.sm) {
                Text("No Identities Yet")
                    .font(.title2.weight(.bold))
                Text("Add a Canvas account to start fanning out attendance requests.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Spacing.xxl)
            }

            Button {
                showAddSheet = true
            } label: {
                Label("Add First Identity", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.md)
                    .background(Palette.accentGradient)
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Group header

    private func groupHeader(
        title: String, count: Int, icon: String, color: Color,
        expanded: Bool, onToggle: @escaping () -> Void
    ) -> some View {
        Button(action: onToggle) {
            HStack(spacing: Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 26, height: 26)
                    Image(systemName: icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                }
                Text(title)
                    .foregroundStyle(Color(.label))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(color.opacity(0.15))
                    .clipShape(Capsule())
                    .foregroundStyle(color)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.secondary)
                    .font(.caption.weight(.semibold))
            }
        }
        .buttonStyle(.plain)
        .textCase(nil)
    }

    // MARK: - Floating dock

    private var floatingDock: some View {
        let canFanOut = !selectedIds.isEmpty
        return HStack(spacing: Spacing.sm + 2) {
            Button {
                showAddSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.subheadline.weight(.semibold))
                    Text("Add Identity")
                        .font(.subheadline.weight(.medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Radius.inner))
                .foregroundStyle(Color(.label))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.inner)
                        .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)

            Button {
                guard canFanOut else { return }
                showScanner = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.subheadline.weight(.semibold))
                    Text(canFanOut ? "Fan-out · \(selectedIds.count)" : "Fan-out")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    canFanOut
                    ? AnyShapeStyle(Palette.accentGradient)
                    : AnyShapeStyle(Color(.systemFill))
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.inner))
                .foregroundStyle(canFanOut ? .white : Color(.secondaryLabel))
                .shadow(color: canFanOut ? Palette.accent.opacity(0.35) : .clear,
                        radius: canFanOut ? 8 : 0, x: 0, y: 4)
            }
            .disabled(!canFanOut)
            .buttonStyle(.plain)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: canFanOut)
        }
        .padding(Spacing.md)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
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
            Image(systemName: "folder").foregroundStyle(Color(hex: 0xB8A2FF))
            Text(course.name)
                .foregroundStyle(Color(hex: 0xB8A2FF))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer()
            Text("\(memberCount)").font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 2)
                .background(Color(hex: 0xB8A2FF).opacity(0.15)).clipShape(Capsule())
                .foregroundStyle(Color(hex: 0xB8A2FF))
            if memberCount > 0 {
                Button(action: onToggleAll) {
                    Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(Color(hex: 0xB8A2FF))
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
