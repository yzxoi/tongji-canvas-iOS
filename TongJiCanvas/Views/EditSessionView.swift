import SwiftUI

struct EditSessionView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var repo: SessionRepository

    let session: UserSession
    @State private var displayName: String
    @State private var accessToken: String
    @State private var selectedGroupIds: Set<UUID>

    init(session: UserSession) {
        self.session = session
        _displayName = State(initialValue: session.displayName)
        _accessToken = State(initialValue: session.accessToken ?? "")
        _selectedGroupIds = State(initialValue: [])
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Display Name", text: $displayName)
                    TextEditor(text: $accessToken)
                        .frame(minHeight: 100)
                }
                if !repo.courses.isEmpty {
                    Section("Groups") {
                        ForEach(repo.courses) { course in
                            Toggle(course.name, isOn: Binding(
                                get: { selectedGroupIds.contains(course.id) },
                                set: { if $0 { selectedGroupIds.insert(course.id) } else { selectedGroupIds.remove(course.id) } }
                            ))
                        }
                    }
                }
            }
            .navigationTitle("Edit Identity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        var updated = session
                        updated.displayName = displayName
                        updated.accessToken = accessToken.isEmpty ? nil : accessToken
                        repo.update(updated)
                        for i in repo.courses.indices {
                            let cid = repo.courses[i].id
                            var course = repo.courses[i]
                            if selectedGroupIds.contains(cid) {
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
                selectedGroupIds = Set(repo.courses.filter { $0.memberIds.contains(session.id) }.map(\.id))
            }
        }
    }
}
