import SwiftUI

struct ManualAddView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var repo: SessionRepository

    @State private var displayName = ""
    @State private var accessToken = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("用户信息") {
                    TextField("用户昵称", text: $displayName)
                    TextEditor(text: $accessToken)
                        .frame(minHeight: 100)
                        .overlay(
                            Group {
                                if accessToken.isEmpty {
                                    Text("认证信息 (Cookies)")
                                        .foregroundStyle(.tertiary)
                                        .padding(4)
                                        .allowsHitTesting(false)
                                }
                            }, alignment: .topLeading
                        )
                }
            }
            .navigationTitle("手动录入 Cookies")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("添加") {
                        guard !displayName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        repo.addOrUpdate(displayName: displayName, accessToken: accessToken.isEmpty ? nil : accessToken)
                        dismiss()
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
