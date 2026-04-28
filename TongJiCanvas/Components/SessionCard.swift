import SwiftUI

// MARK: - Avatar colour palette (mirrors Android)

private let avatarStyles: [(bg: Color, fg: Color)] = [
    (Color(hex: 0xE6DEFF), Color(hex: 0x6A49FF)),
    (Color(hex: 0xFCE1EF), Color(hex: 0xD23C7B)),
    (Color(hex: 0xFFE4D6), Color(hex: 0xC05B29)),
    (Color(hex: 0xE1F6F3), Color(hex: 0x1E8A78)),
    (Color(hex: 0xE0ECFF), Color(hex: 0x1E5BB8)),
    (Color(hex: 0xF7E5FF), Color(hex: 0x8A32B8))
]

// MARK: - SessionCard

struct SessionCard: View {
    let session: UserSession
    @Binding var isSelected: Bool
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            avatarView
            VStack(alignment: .leading, spacing: 4) {
                Text(session.displayName)
                    .font(.headline)
                    .lineLimit(1)
                statusLabel
            }
            Spacer()
            Toggle("", isOn: $isSelected)
                .labelsHidden()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(isSelected ? Color(hex: 0xB8A2FF) : Color(.separator), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: isSelected ? Color(hex: 0xB8A2FF).opacity(0.35) : Color(.systemBackground).opacity(0.0),
                radius: isSelected ? 8 : 0, y: isSelected ? 2 : 0)
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label("删除", systemImage: "trash")
            }
        }
    }

    private var avatarView: some View {
        let style = avatarStyles[abs(session.displayName.hashValue) % avatarStyles.count]
        let initial = session.displayName.first.map(String.init)?.uppercased() ?? "?"
        return ZStack {
            Circle().fill(style.bg)
            Text(initial).font(.headline).foregroundStyle(style.fg)
        }
        .frame(width: 48, height: 48)
    }

    private var statusLabel: some View {
        HStack(spacing: 6) {
            if !session.hasCredentials {
                Circle().fill(Color.orange).frame(width: 6, height: 6)
            }
            Text(session.hasCredentials ? "已保存认证信息" : "等待手动验证")
                .font(.caption)
                .foregroundStyle(session.hasCredentials ? Color(.secondaryLabel) : .orange)
        }
    }
}
