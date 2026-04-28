import SwiftUI

struct AddCourseView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var repo: SessionRepository

    @State private var courseName = ""
    @State private var selectedMemberIds: Set<UUID> = []

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Group Name", text: $courseName) }
                if !repo.sessions.isEmpty {
                    Section("Members") {
                        ForEach(repo.sessions) { s in
                            Toggle(s.displayName, isOn: Binding(
                                get: { selectedMemberIds.contains(s.id) },
                                set: { if $0 { selectedMemberIds.insert(s.id) } else { selectedMemberIds.remove(s.id) } }
                            ))
                        }
                    }
                }
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
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
