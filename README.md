# 同济大学 Canvas 批量签到助手 — iOS 版

[![CI](https://github.com/yzxoi/tongji-canvas-iOS/actions/workflows/ci.yml/badge.svg)](https://github.com/yzxoi/tongji-canvas-iOS/actions/workflows/ci.yml)

> 同济大学 Canvas 系统课堂签到的 iOS 原生客户端，功能对齐 [Android 版](https://github.com/mmmlllnnn/TongJi_Canvas)。

---

## ✨ 功能特性

- **一键批量签到**：同时为多个账号完成课堂签到，并发执行、互不干扰
- **在线登录自动捕获**：内嵌 WKWebView 完成统一认证，自动提取并保存认证信息（Cookie 永久有效，只需获取一次）
- **手动录入 Cookie**：支持直接粘贴已有认证信息添加账号
- **课程分组管理**：按课程将账号分组，一键选中整组参与签到
- **剪贴板导入导出**：JSON 格式批量迁移账号与课程数据
- **相机二维码扫描**：AVFoundation 原生扫码，支持小尺寸、倾斜二维码

## 📱 界面预览

| 主界面 | 登录页 | 扫码页 | 批量签到 |
|:---:|:---:|:---:|:---:|
| 账号列表 + 分组 | 统一认证 WebView | 实时扫描 | 并发进度卡片 |

## 🛠 技术架构

```
TongJiCanvas/
├── Models/
│   ├── UserSession.swift        # 用户模型（Codable，accessToken 存 Keychain）
│   └── Course.swift             # 课程/分组模型
├── Data/
│   └── SessionRepository.swift  # CRUD + 导入导出，@MainActor，ObservableObject
├── Extensions/
│   └── Color+Hex.swift          # Color(hex:) 扩展
├── Utils/
│   ├── CookieHelper.swift       # Cookie 字符串解析 / WKWebsiteDataStore 注入
│   └── KeychainHelper.swift     # Keychain 安全存储 accessToken
├── Components/
│   ├── WebView.swift            # WKWebView 封装
│   └── SessionCard.swift        # 用户卡片 UI 组件
└── Views/
    ├── MainView.swift           # 主界面：账号列表、课程分组、底部操作栏
    ├── LoginView.swift          # OAuth2 登录 WebView
    ├── LoginViewModel.swift     # 登录逻辑 ViewModel
    ├── ManualAddView.swift      # 手动录入 Cookies
    ├── EditSessionView.swift    # 编辑用户信息
    ├── AddCourseView.swift      # 新建课程分组
    ├── EditCourseView.swift     # 编辑课程分组
    ├── ScannerView.swift        # 相机扫码（AVFoundation）
    └── BatchSignView.swift      # 并发批量签到 + 实时进度
TongJiCanvasTests/
├── SessionRepositoryTests.swift # 仓库层单元测试
└── KeychainHelperTests.swift    # Keychain 单元测试
```

**关键技术选型：**

| 功能 | 方案 | 说明 |
|------|------|------|
| UI 框架 | SwiftUI | 声明式 UI，全面覆盖 |
| 状态管理 | `ObservableObject` + `@EnvironmentObject` | 共享 `SessionRepository` |
| WebView | `WKWebView` + `WKWebsiteDataStore` | 每用户独立非持久化数据存储，真并发 |
| Cookie 捕获 | `WKHTTPCookieStoreObserver` | 异步监听 `_canvas_middle_session` 写入 |
| 批量签到 | `async/await` + `withTaskGroup` | 所有用户并发签到，互不阻塞 |
| 扫码 | `AVCaptureMetadataOutput` | 系统原生，支持 QR / DataMatrix / Aztec |
| 持久化 | `UserDefaults` + `JSONEncoder` | 轻量，无需 Core Data |

**iOS vs Android Cookie 隔离对比：**

Android 版使用全局 `CookieManager`，批量签到时需逐用户顺序清空重设，存在竞争风险。iOS 版为每个用户创建独立的 `WKWebsiteDataStore.nonPersistent()` 实例，Cookie 完全沙箱隔离，多用户真正并发。

## 📋 使用指南

1. **添加账号**
   - 点击底部 **添加账号** → **在线登录添加**，在统一认证页完成登录，系统自动提取 Cookie
   - 或选择 **手动录入 Cookies**，粘贴已有认证信息

2. **管理分组**（可选）
   - 点击 **新建课程分组**，将账号按课程分类，便于快速全选

3. **批量签到**
   - 勾选参与本次签到的账号（Toggle 开关）
   - 点击底部 **一键签到**，对准课堂二维码扫描
   - 进入签到页，实时查看每个账号的签到结果

4. **导入导出**
   - 右上角菜单 → **导出到剪贴板**，JSON 格式包含账号与课程分组
   - 在新设备粘贴后 → **从剪贴板导入**，一键迁移

## ⚙️ 构建要求

| 项目 | 要求 |
|------|------|
| Xcode | 15.0+ |
| iOS 最低版本 | 17.0 |
| Swift | 6.0 |
| 第三方依赖 | 无 |

### 构建步骤

```bash
# 克隆仓库
git clone git@github.com:yzxoi/tongji-canvas-iOS.git
cd tongji-canvas-iOS

# （可选）用 xcodegen 重新生成项目文件
brew install xcodegen
xcodegen generate

# 用 Xcode 打开
open TongJiCanvas.xcodeproj
```

在 Xcode 中选择目标设备，配置开发者签名（Signing），Build & Run。

### 权限说明

| 权限 | 用途 |
|------|------|
| `NSCameraUsageDescription` | 扫描签到二维码 |

## 📖 认证原理

同济 Canvas 采用统一身份认证（IAM）+ OAuth2.0 流程，登录后 `canvas.tongji.edu.cn` 域下会写入 Session Cookie（`_canvas_middle_session` 等）。该 Cookie 在服务端绑定用户身份，**长期有效**，无需重复登录。

签到 URL 格式：
```
https://canvas.tongji.edu.cn/lms/mobile/forscan?courseCode=XXXX&rollCallToken=XXXX
```

携带用户 Cookie 访问该 URL，若页面返回"签到成功"或"已签过"则视为完成。

## 🤝 相关项目

- [Android 版](https://github.com/mmmlllnnn/TongJi_Canvas) — 原版，Kotlin + Jetpack Compose
- [Web 版](https://github.com/mmmlllnnn/TongJi_Canvas_Web) — 无需安装，浏览器直接使用
