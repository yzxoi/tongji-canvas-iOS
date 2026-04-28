import SwiftUI

// MARK: - About view

struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    descriptionSection
                    linksSection
                    creditsSection
                }
                .padding(20)
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 56))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: 0x7C3AED), Color(hex: 0x9333EA)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )

            Text("Canvas Session Multiplexer")
                .font(.title2.weight(.bold))

            Text("A Concurrent Per-User HTTP Proxy")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("v1.0 · Swift 6 · iOS 17+")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 20)
    }

    // MARK: - Description

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("""
            An experimental iOS client that explores per-user HTTP session isolation for concurrent multi-account attendance submission on Tongji University's Canvas LMS.

            Instead of serialising requests through a shared Cookie store (the standard approach), this implementation injects credentials as explicit per-request Cookie headers over ephemeral URLSession instances — achieving true task-level parallelism under Swift 6 structured concurrency.

            Built for research, testing, and educational purposes.
            """)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Source links

    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Repositories")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            linkRow(
                title: "Session Multiplexer (iOS)",
                description: "github.com/yzxoi/tongji-canvas-iOS",
                url: "https://github.com/yzxoi/tongji-canvas-iOS",
                icon: "apple.logo"
            )

            Divider()

            linkRow(
                title: "TongJi Canvas (Android)",
                description: "github.com/mmmlllnnn/TongJi_Canvas",
                url: "https://github.com/mmmlllnnn/TongJi_Canvas",
                icon: "gearshape.2"
            )

            Divider()

            linkRow(
                title: "TongJi Canvas (Web)",
                description: "github.com/mmmlllnnn/TongJi_Canvas_Web",
                url: "https://github.com/mmmlllnnn/TongJi_Canvas_Web",
                icon: "globe"
            )
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func linkRow(title: String, description: String, url: String, icon: String) -> some View {
        Button {
            if let u = URL(string: url) { openURL(u) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(Color(hex: 0x7C3AED))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color(.label))
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "arrow.up.forward.app")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Credits

    private var creditsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Acknowledgements")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("""
            The Android and Web reference implementations by mmmlllnnn provided the initial API analysis and problem framing. This iOS port investigates the same problem space under a different concurrency model — replacing sequential CookieManager mutation with per-request header injection.

            All trademarks and service marks are property of their respective owners.
            """)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
