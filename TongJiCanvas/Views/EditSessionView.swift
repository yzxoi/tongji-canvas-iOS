import SwiftUI

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
