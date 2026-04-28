import SwiftUI

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
