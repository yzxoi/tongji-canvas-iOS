import SwiftUI

struct ManualAddView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var repo: SessionRepository

    @State private var displayName = ""
    @State private var accessToken = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Display Name", text: $displayName)
                    TextEditor(text: $accessToken)
                        .frame(minHeight: 100)
                        .overlay(
                            Group {
                                if accessToken.isEmpty {
                                    Text("Credential (Cookie string)")
                                        .foregroundStyle(.tertiary)
                                        .padding(4)
                                        .allowsHitTesting(false)
                                }
                            }, alignment: .topLeading
                        )
                }
            }
            .navigationTitle("Paste Credential")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
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
