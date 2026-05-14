import SwiftUI

// MARK: - About view

struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.xl) {
                    heroSection
                    descriptionSection
                    linksSection
                    creditsSection
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, Spacing.xxl)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Hero (replaces flat header)

    private var heroSection: some View {
        VStack(spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(Palette.heroGradient)
                    .frame(width: 96, height: 96)
                    .shadow(color: Palette.accent.opacity(0.4), radius: 16, y: 8)

                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.top, Spacing.lg)

            VStack(spacing: Spacing.xs) {
                Text("Canvas Session Multiplexer")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                Text("A Concurrent Per-User HTTP Proxy")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: Spacing.sm) {
                metaPill(icon: "checkmark.seal.fill", text: "v1.2")
                metaPill(icon: "swift", text: "Swift 6")
                metaPill(icon: "apple.logo", text: "iOS 17+")
            }
        }
    }

    private func metaPill(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(Palette.accentDeep)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 6)
            .background(Palette.accentSurface, in: Capsule())
    }

    // MARK: - Description

    private var descriptionSection: some View {
        sectionCard(title: "Overview", icon: "doc.text.magnifyingglass") {
            Text("""
            An experimental iOS client that explores per-user HTTP session isolation for concurrent multi-account attendance submission on Tongji University's Canvas LMS.

            Instead of serialising requests through a shared Cookie store (the standard approach), this implementation injects credentials as explicit per-request Cookie headers over ephemeral URLSession instances — achieving true task-level parallelism under Swift 6 structured concurrency.

            Built for research, testing, and educational purposes.
            """)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Source links

    private var linksSection: some View {
        sectionCard(title: "Repositories", icon: "chevron.left.forwardslash.chevron.right") {
            VStack(spacing: 0) {
                linkRow(
                    title: "Session Multiplexer (iOS)",
                    description: "github.com/yzxoi/tongji-canvas-iOS",
                    url: "https://github.com/yzxoi/tongji-canvas-iOS",
                    icon: "apple.logo"
                )
                Divider().padding(.leading, 52)
                linkRow(
                    title: "TongJi Canvas (Android)",
                    description: "github.com/mmmlllnnn/TongJi_Canvas",
                    url: "https://github.com/mmmlllnnn/TongJi_Canvas",
                    icon: "candybarphone"
                )
                Divider().padding(.leading, 52)
                linkRow(
                    title: "TongJi Canvas (Web)",
                    description: "github.com/mmmlllnnn/TongJi_Canvas_Web",
                    url: "https://github.com/mmmlllnnn/TongJi_Canvas_Web",
                    icon: "globe"
                )
            }
        }
    }

    private func linkRow(title: String, description: String, url: String, icon: String) -> some View {
        Button {
            if let u = URL(string: url) { openURL(u) }
        } label: {
            HStack(spacing: Spacing.md) {
                ZStack {
                    Circle()
                        .fill(Palette.accentSurface)
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(.label))
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "arrow.up.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, Spacing.md)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Credits

    private var creditsSection: some View {
        sectionCard(title: "Acknowledgements", icon: "hands.sparkles") {
            Text("""
            The Android and Web reference implementations by mmmlllnnn provided the initial API analysis and problem framing. This iOS port investigates the same problem space under a different concurrency model — replacing sequential CookieManager mutation with per-request header injection.

            All trademarks and service marks are property of their respective owners.
            """)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Section card shell

    @ViewBuilder
    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.accent)
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color(.label))
                    .textCase(.uppercase)
            }
            content()
        }
        .padding(Spacing.xl)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: Radius.panel))
    }
}
