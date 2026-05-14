import SwiftUI

// MARK: - Avatar colour palette

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
        HStack(spacing: Spacing.lg) {
            avatarView
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(session.displayName)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(Color(.label))
                statusLabel
            }
            Spacer(minLength: Spacing.sm)
            selectionIndicator
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.vertical, Spacing.md + 2)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(
                    isSelected ? Palette.accent.opacity(0.85) : Color(.separator).opacity(0.45),
                    lineWidth: isSelected ? 1.5 : 0.8
                )
        )
        .shadow(
            color: isSelected ? Palette.accent.opacity(0.28) : Color.black.opacity(0.04),
            radius: isSelected ? 10 : 3,
            x: 0,
            y: isSelected ? 5 : 1
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // Tap toggles selection — primary use case is fan-out.
            // Edit / delete remain available via the trailing swipe actions.
            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                isSelected.toggle()
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            .tint(Palette.accent)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
    }

    // MARK: - Avatar

    private var avatarView: some View {
        let style = avatarStyles[abs(session.displayName.hashValue) % avatarStyles.count]
        let initial = session.displayName.first.map(String.init)?.uppercased() ?? "?"
        return ZStack {
            Circle().fill(style.bg)
            Text(initial)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(style.fg)
        }
        .frame(width: 44, height: 44)
        .overlay(
            Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1)
        )
    }

    // MARK: - Status

    private var statusLabel: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(session.hasCredentials ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
            Text(session.hasCredentials ? "Credential stored" : "Awaiting credential")
                .font(.caption)
                .foregroundStyle(session.hasCredentials ? Color(.secondaryLabel) : .orange)
        }
    }

    // MARK: - Selection indicator (replaces stock Toggle)

    private var selectionIndicator: some View {
        ZStack {
            Circle()
                .fill(isSelected ? Palette.accent : Color(.tertiarySystemFill))
                .frame(width: 28, height: 28)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    // MARK: - Background

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Radius.card)
            .fill(Color(.systemBackground))
    }
}
