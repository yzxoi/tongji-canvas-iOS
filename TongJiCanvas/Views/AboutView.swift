import SwiftUI

// MARK: - About view

struct AboutView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // App icon + name
                    headerSection

                    // Description
                    descriptionSection

                    // Source code links
                    linksSection

                    // Credits
                    creditsSection
                }
                .padding(20)
            }
            .navigationTitle("关于")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(hex: 0x7C3AED), Color(hex: 0x9333EA)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )

            Text("Canvas 批量签到")
                .font(.title2.weight(.bold))

            Text("v1.0")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 20)
    }

    // MARK: - Description

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("项目简介")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("同济大学 Canvas 系统课堂签到 iOS 原生客户端。支持多人并发批量签到、OAuth2 自动登录捕获 Cookie、课程分组管理、二维码扫描等功能。Cookie 长期有效，只需获取一次。")
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
            Text("项目仓库")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            linkRow(
                title: "iOS 版",
                description: "github.com/yzxoi/tongji-canvas-iOS",
                url: "https://github.com/yzxoi/tongji-canvas-iOS",
                icon: "apple.logo"
            )

            Divider()

            linkRow(
                title: "Android 版",
                description: "github.com/mmmlllnnn/TongJi_Canvas",
                url: "https://github.com/mmmlllnnn/TongJi_Canvas",
                icon: "gearshape.2"
            )

            Divider()

            linkRow(
                title: "Web 版",
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
            Text("致谢")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("感谢 Android 版和 Web 版的原作者 mmmlllnnn 提供的参考实现与思路。本 iOS 版在保持核心功能一致的基础上，针对 Apple 平台做了原生适配与优化。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
        }
        .padding(20)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
}
