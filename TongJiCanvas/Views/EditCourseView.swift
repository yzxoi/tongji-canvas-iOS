import SwiftUI

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
