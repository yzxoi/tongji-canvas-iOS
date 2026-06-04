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
    @State private var showEmptyAddSheet   = false
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
            // MARK: Groups (quick-select). Always shown when any course exists.
            if !repo.courses.isEmpty {
                Section {
                    ForEach(repo.courses) { course in
                        let members = repo.sessions.filter { course.memberIds.contains($0.id) }
                        CourseCard(
                            course: course,
                            members: members,
                            selectedIds: selectedIds,
                            onToggleAll: { toggleCourseSelection(members) },
                            onEdit: { editingGroup = course }
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color(.systemGroupedBackground))
                    }

                    newGroupRow
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color(.systemGroupedBackground))
                } header: {
                    sectionTitle("Groups", icon: "folder.fill", count: repo.courses.count)
                }
            } else {
                // No courses yet — show the New Group row alone so users discover the feature.
                Section {
                    newGroupRow
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color(.systemGroupedBackground))
                } header: {
                    sectionTitle("Groups", icon: "folder.fill", count: 0)
                }
            }

            // MARK: Identities. The primary roster.
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
                identitiesHeader
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.visible)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Toggle helper for course selection

    private func toggleCourseSelection(_ members: [UserSession]) {
        let memberIds = Set(members.map(\.id))
        guard !memberIds.isEmpty else { return }
        let allInSelection = members.allSatisfy { selectedIds.contains($0.id) }
        if allInSelection {
            selectedIds.subtract(memberIds)            // deselect this course's members
        } else {
            selectedIds.formUnion(memberIds)           // add this course's members
        }
    }

    // MARK: - Identities header (with select-all toggle)

    private var identitiesHeader: some View {
        let allSelected = !repo.sessions.isEmpty
            && repo.sessions.allSatisfy { selectedIds.contains($0.id) }
        let partiallySelected = !allSelected
            && repo.sessions.contains(where: { selectedIds.contains($0.id) })

        return HStack(spacing: Spacing.sm) {
            Button {
                allUsersExpanded.toggle()
            } label: {
                HStack(spacing: Spacing.sm) {
                    ZStack {
                        Circle()
                            .fill(Palette.accent.opacity(0.12))
                            .frame(width: 26, height: 26)
                        Image(systemName: "person.2.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.accent)
                    }
                    Text("Identities")
                        .foregroundStyle(Color(.label))
                        .font(.subheadline.weight(.semibold))
                    Text("\(repo.sessions.count)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(Palette.accent.opacity(0.15))
                        .clipShape(Capsule())
                        .foregroundStyle(Palette.accent)
                    Image(systemName: allUsersExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                        .font(.caption.weight(.semibold))
                }
            }
            .buttonStyle(.plain)

            Spacer()

            // Select all / clear, only shown when there's something to act on
            if !repo.sessions.isEmpty {
                Button {
                    if allSelected {
                        selectedIds.subtract(repo.sessions.map(\.id))
                    } else {
                        selectedIds.formUnion(repo.sessions.map(\.id))
                    }
                } label: {
                    Text(allSelected ? "Clear" : (partiallySelected ? "Select all" : "Select all"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, 5)
                        .background(Palette.accent.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .textCase(nil)
    }

    // MARK: - Section title (used for the Groups section)

    private func sectionTitle(_ title: String, icon: String, count: Int) -> some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(Palette.accent.opacity(0.12))
                    .frame(width: 26, height: 26)
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.accent)
            }
            Text(title)
                .foregroundStyle(Color(.label))
                .font(.subheadline.weight(.semibold))
            if count > 0 {
                Text("\(count)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Palette.accent.opacity(0.15))
                    .clipShape(Capsule())
                    .foregroundStyle(Palette.accent)
            }
            Spacer()
        }
        .textCase(nil)
    }

    // MARK: - "New Group" row

    private var newGroupRow: some View {
        Button {
            showAddGroup = true
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Palette.accent)
                Text("New Group")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.accent.opacity(0.6))
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.accentSurface.opacity(0.6))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(Palette.accent.opacity(0.18), style: StrokeStyle(lineWidth: 1.2, dash: [6, 4]))
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        }
        .buttonStyle(.plain)
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
                showEmptyAddSheet = true
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
            .confirmationDialog("Add Identity", isPresented: $showEmptyAddSheet) {
                addIdentityDialogActions
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }


    // MARK: - Floating dock

    // MARK: - Floating dock (integrates selection bar + action buttons)

    private var floatingDock: some View {
        let canFanOut = !selectedIds.isEmpty
        let validCount = selectedIds.intersection(Set(repo.sessions.map(\.id))).count
        let hasSelection = validCount > 0

        return VStack(spacing: 0) {
            // Selection bar — collapses into the dock when nothing is selected.
            // Keeps a single material+shadow layer for a smooth size animation.
            if hasSelection {
                selectionBar(count: validCount)
            }

            // Action buttons — always present.
            dockButtons(canFanOut: canFanOut)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 4)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: hasSelection)
    }

    @ViewBuilder
    private var addIdentityDialogActions: some View {
        Button("Sign in via IAM (auto-capture)") { showOAuthLogin = true }
        Button("Paste Credential") { showManualAdd = true }
        Button("Cancel", role: .cancel) {}
    }

    /// Top bar that surfaces "N selected · Clear" while the dock holds buttons below.
    /// Background and corner-radius are inherited from the parent VStack clip, so
    /// the only thing that animates is this row's height/opacity — no separate
    /// layer pop-in.
    private func selectionBar(count: Int) -> some View {
        HStack(spacing: Spacing.sm) {
            ZStack {
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text("\(count) selected for fan-out")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Palette.accentDeep)
            Spacer(minLength: Spacing.sm)
            Button {
                selectedIds.removeAll()
            } label: {
                Text("Clear")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.7), in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(Palette.accent.opacity(0.2), lineWidth: 0.5)
                    )
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.horizontal, Spacing.md + 2)
        .padding(.vertical, Spacing.sm + 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.accentSurface.opacity(0.65))
        // Asymmetric transition: slide in from top of the dock, slide out crisper.
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal:   .move(edge: .bottom).combined(with: .opacity)
        ))
    }

    /// Add-identity + Fan-out CTA row.  Always visible.
    private func dockButtons(canFanOut: Bool) -> some View {
        HStack(spacing: Spacing.sm + 2) {
            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color(.label))
                    .frame(width: 56, height: 56)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Radius.inner))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.inner)
                            .strokeBorder(Color(.separator).opacity(0.5), lineWidth: 0.5)
                    )
            }
            .buttonStyle(PressableButtonStyle())
            .confirmationDialog("Add Identity", isPresented: $showAddSheet) {
                addIdentityDialogActions
            }

            Button {
                guard canFanOut else { return }
                showScanner = true
            } label: {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 18, weight: .bold))
                    Text(canFanOut ? "Fan-out \(selectedIds.count)" : "Select identities first")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    if canFanOut {
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .padding(.horizontal, Spacing.lg)
                .background(
                    canFanOut
                    ? AnyShapeStyle(Palette.accentGradient)
                    : AnyShapeStyle(Color(.systemFill))
                )
                .clipShape(RoundedRectangle(cornerRadius: Radius.inner))
                .foregroundStyle(canFanOut ? .white : Color(.secondaryLabel))
                .shadow(color: canFanOut ? Palette.accent.opacity(0.4) : .clear,
                        radius: canFanOut ? 10 : 0, x: 0, y: 5)
            }
            .disabled(!canFanOut)
            .buttonStyle(PressableButtonStyle())
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: canFanOut)
        }
        .padding(.horizontal, Spacing.sm + 2)
        .padding(.vertical, Spacing.sm + 2)
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
        // Quick theme toggle — single tap cycles System → Light → Dark → System.
        ToolbarItem(placement: .topBarLeading) {
            let current = ColorSchemeMode(rawValue: schemeMode) ?? .system
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    schemeMode = (schemeMode + 1) % 3
                }
            } label: {
                Image(systemName: current.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace))
            }
            .accessibilityLabel("Theme: \(current.label)")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Palette.accent)
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

// MARK: - Course card (full-width, primary-action = toggle select-all)

private struct CourseCard: View {
    let course: Course
    let members: [UserSession]
    let selectedIds: Set<UUID>
    let onToggleAll: () -> Void
    let onEdit: () -> Void

    /// True when every member of this course is in the global selection.
    private var allSelected: Bool {
        !members.isEmpty && members.allSatisfy { selectedIds.contains($0.id) }
    }
    /// True when *some but not all* members are selected.
    private var partiallySelected: Bool {
        !allSelected && members.contains(where: { selectedIds.contains($0.id) })
    }
    private var selectedInCourse: Int {
        members.filter { selectedIds.contains($0.id) }.count
    }

    var body: some View {
        HStack(spacing: Spacing.md) {
            folderIcon
            VStack(alignment: .leading, spacing: 6) {
                Text(course.name)
                    .font(.headline)
                    .foregroundStyle(allSelected ? .white : Color(.label))
                    .lineLimit(1)
                memberRow
            }
            Spacer(minLength: Spacing.sm)
            selectionDot
            editButton
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md + 2)
        .frame(minHeight: 76)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
        .shadow(
            color: allSelected ? Palette.accent.opacity(0.35) : Color.black.opacity(0.05),
            radius: allSelected ? 12 : 4,
            x: 0,
            y: allSelected ? 6 : 2
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggleAll)   // implicit animations below drive the visual feedback
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: allSelected)
        .animation(.easeInOut(duration: 0.2), value: partiallySelected)
    }

    // MARK: - Folder icon

    private var folderIcon: some View {
        ZStack {
            Circle()
                .fill(allSelected ? Color.white.opacity(0.22) : Palette.accentSurface)
                .frame(width: 46, height: 46)
            Image(systemName: "folder.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(allSelected ? .white : Palette.accent)
        }
    }

    // MARK: - Avatar stack + count

    @ViewBuilder
    private var memberRow: some View {
        if members.isEmpty {
            Text("No members — tap menu to add")
                .font(.caption)
                .foregroundStyle(allSelected ? .white.opacity(0.85) : .secondary)
        } else {
            HStack(spacing: Spacing.sm) {
                avatarStack
                Text(memberSummary)
                    .font(.caption.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(allSelected ? .white.opacity(0.95) : .secondary)
            }
        }
    }

    private var memberSummary: String {
        if allSelected {
            return "All \(members.count) selected"
        } else if partiallySelected {
            return "\(selectedInCourse) of \(members.count) selected"
        } else {
            return "\(members.count) \(members.count == 1 ? "member" : "members")"
        }
    }

    private var avatarStack: some View {
        HStack(spacing: -8) {
            ForEach(Array(members.prefix(3).enumerated()), id: \.element.id) { _, m in
                miniAvatar(for: m)
            }
            if members.count > 3 {
                ZStack {
                    Circle()
                        .fill(allSelected ? Color.white.opacity(0.25) : Color(.tertiarySystemFill))
                        .frame(width: 22, height: 22)
                    Text("+\(members.count - 3)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(allSelected ? .white : .secondary)
                }
                .overlay(
                    Circle().strokeBorder(allSelected ? Palette.accent : Color(.systemBackground), lineWidth: 2)
                )
            }
        }
    }

    private func miniAvatar(for session: UserSession) -> some View {
        let initial = session.displayName.first.map(String.init)?.uppercased() ?? "?"
        return ZStack {
            Circle()
                .fill(allSelected ? Color.white.opacity(0.25) : Palette.accentSurface)
                .frame(width: 22, height: 22)
            Text(initial)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(allSelected ? .white : Palette.accentDeep)
        }
        .overlay(
            Circle().strokeBorder(allSelected ? Palette.accent : Color(.systemBackground), lineWidth: 2)
        )
    }

    // MARK: - Selection dot (primary feedback)

    private var selectionDot: some View {
        ZStack {
            Circle()
                .fill(dotFill)
                .frame(width: 32, height: 32)
                .overlay(
                    Circle().strokeBorder(dotStroke, lineWidth: 1.5)
                )
            if allSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Palette.accent)
                    .transition(.scale.combined(with: .opacity))
            } else if partiallySelected {
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 10, height: 10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var dotFill: Color {
        if allSelected { return .white }
        if partiallySelected { return Palette.accentSurface }
        return Color(.tertiarySystemFill).opacity(0.6)
    }
    private var dotStroke: Color {
        if allSelected { return .clear }
        return Color(.separator).opacity(0.5)
    }

    // MARK: - Edit button (secondary action, kept compact)

    private var editButton: some View {
        Button(action: onEdit) {
            Image(systemName: "pencil")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(allSelected ? .white : Palette.accent)
                .frame(width: 32, height: 32)
                .background(
                    allSelected ? Color.white.opacity(0.2) : Palette.accentSurface,
                    in: Circle()
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Card background

    @ViewBuilder
    private var cardBackground: some View {
        if allSelected {
            Palette.accentGradient
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        } else {
            Color(.systemBackground)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        }
    }

    private var borderColor: Color {
        if allSelected { return .clear }
        if partiallySelected { return Palette.accent.opacity(0.6) }
        return Color(.separator).opacity(0.4)
    }
    private var borderWidth: CGFloat {
        partiallySelected ? 1.5 : 0.8
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
