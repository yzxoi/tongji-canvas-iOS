# TongJi Canvas Batch Attendance — iOS Client

[![CI](https://github.com/yzxoi/tongji-canvas-iOS/actions/workflows/ci.yml/badge.svg)](https://github.com/yzxoi/tongji-canvas-iOS/actions/workflows/ci.yml)

A native iOS application for concurrent multi-account attendance submission on the Tongji University Canvas LMS. The client is functionally equivalent to the [reference Android implementation](https://github.com/mmmlllnnn/TongJi_Canvas), re-architected for the iOS platform under Swift 6 strict concurrency.

---

## Overview

The Tongji University Canvas system gates attendance credit behind a session-cookie–authenticated HTTP endpoint (`/lms/mobile/forscan?courseCode=…&rollCallToken=…`). This application manages per-account credential lifecycle, submits concurrent HTTP requests to the attendance endpoint, and surfaces per-account results in real time.

The central engineering challenge is **per-user session isolation at concurrency scale**: unlike Android's globally mutable `CookieManager`, which forces sequential per-user cookie replacement, this implementation assigns each account an independent ephemeral `URLSession` configured with an explicit `Cookie` header — eliminating shared state and enabling true task-level parallelism.

---

## Feature Set

| Capability | Implementation |
|---|---|
| Concurrent batch sign-in | `withTaskGroup` over all selected accounts; each task is fully isolated |
| OAuth2 credential capture | Embedded `WKWebView` with `WKHTTPCookieStoreObserver`; token persisted to Keychain |
| Manual credential entry | Paste-based cookie import via `UITextView` |
| Course-based account grouping | Many-to-many `Course ↔ UserSession` relationship; one-tap group selection |
| JSON import / export | Clipboard-based migration; round-trip stable across app reinstalls |
| QR code scanning | `AVCaptureMetadataOutput` with confirmation UI; supports skewed/small codes |
| Persistent credential storage | `UserDefaults` for metadata, Keychain for session tokens |

---

## Architecture

```
TongJiCanvas/
├── Models/
│   ├── UserSession.swift        # Value type; accessToken excluded from JSON encoding
│   └── Course.swift             # Course/group model with member UUID references
├── Data/
│   └── SessionRepository.swift  # @MainActor ObservableObject; CRUD + import/export
├── Extensions/
│   └── Color+Hex.swift          # Convenience Color(hex:) initialiser
├── Utils/
│   ├── CookieHelper.swift       # Cookie string parsing; WKWebsiteDataStore injection
│   └── KeychainHelper.swift     # SecItem CRUD wrapper; kSecAttrService-scoped
├── Components/
│   ├── WebView.swift            # Generic WKWebView UIViewRepresentable
│   └── SessionCard.swift        # Reusable account card component
└── Views/
    ├── MainView.swift           # Account list, course groups, action toolbar
    ├── LoginView.swift          # IAM OAuth2 WebView shell
    ├── LoginViewModel.swift     # Cookie capture state machine with countdown
    ├── ManualAddView.swift      # Raw cookie paste entry
    ├── EditSessionView.swift    # Account edit form
    ├── AddCourseView.swift      # Course creation form
    ├── EditCourseView.swift     # Course membership editor
    ├── ScannerView.swift        # AVFoundation QR scanner + confirmation card
    ├── BatchSignView.swift      # Concurrent sign-in progress UI
    └── AboutView.swift          # Application metadata and credits
TongJiCanvasTests/
├── BatchSignViewModelTests.swift  # ViewModel state machine coverage
├── CookieHelperTests.swift        # Cookie string parsing edge cases
├── UserSessionTests.swift         # Model Codable invariants
├── SessionRepositoryTests.swift   # Repository CRUD and import/export
└── KeychainHelperTests.swift      # SecItem read/write/delete correctness
```

---

## Technical Design

### Session Isolation Strategy

Android's `CookieManager` is a process-wide singleton; concurrent sign-in attempts share a single cookie jar and must be serialised. This implementation avoids that bottleneck entirely:

```
Per-account sign-in path
─────────────────────────────────────────────────────────
 URLSession (ephemeral)          ← no shared cookie storage
   httpAdditionalHeaders:
     Cookie: <account token>     ← injected per-request
   timeoutIntervalForRequest: 5s
   httpMaximumConnectionsPerHost: 8
─────────────────────────────────────────────────────────
```

Each account executes an independent `URLRequest` carrying its own `Cookie` header. No shared mutable state is accessed during flight; all accounts can proceed in true parallel.

### Concurrency Model

`BatchSignViewModel` is `@MainActor`-isolated. Network operations are dispatched via `nonisolated static` methods that execute on the cooperative thread pool, returning `SignResult` value types back to the actor:

```swift
// Off-actor network call — no MainActor crossing required
private nonisolated static func performSign(url: URL, cookieValue: String) async -> SignResult

// Coordinated on the actor
private func signAll() async {
    await withTaskGroup(of: Void.self) { group in
        for session in sessions {
            group.addTask { [weak self] in await self?.sign(session: session) }
        }
    }
}
```

### Credential Storage

Session tokens are stored in the iOS Keychain under a per-account UUID key, scoped to `kSecAttrService = "com.tongji.canvas"` with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. `UserSession` deliberately excludes `accessToken` from its `CodingKeys`, preventing accidental token serialisation to `UserDefaults`.

### Login Detection

The `LoginViewModel` observes `WKHTTPCookieStoreObserver` notifications on the default `WKWebsiteDataStore`. Detection requires two conditions to hold simultaneously to guard against false positives:

1. The current URL's host must contain `canvas.tongji.edu.cn` (not an IAM intermediate page)
2. At least one cookie named `_canvas_middle_session` is present in the store

On detection, a 3-second countdown fires before automatic capture, giving the user an opportunity to inspect the result.

---

## Test Suite

48 tests across 5 suites, validated under Swift Testing:

| Suite | Tests | Notes |
|---|---|---|
| `BatchSignViewModelTests` | 13 | progress, counts, `hasActiveSigning`, `toggleExpanded`, `SignStatus` labels/icons |
| `CookieHelperTests` | 9 | `parseCookies` — single, multiple, equals-in-value, empty name, custom domain, real-world string |
| `UserSessionTests` | 5 | UUID generation, `hasCredentials`, Codable round-trip (token exclusion), `Equatable` |
| `SessionRepositoryTests` | 16 | CRUD, Keychain persistence, reload survival, import/export, `selectedIds` |
| `KeychainHelperTests` | 7 | `SecItemAdd`/`SecItemCopyMatching`/`SecItemDelete`, overwrite, empty value, special chars |

`SessionRepositoryTests` is annotated `@Suite(.serialized)` to prevent concurrent `UserDefaults` mutation between test cases. `KeychainHelperTests` uses per-test UUID-scoped keys for full concurrency safety.

---

## Authentication Protocol

Tongji University Canvas implements a Unified Identity Authentication (IAM) flow fronting an OAuth 2.0 authorisation server. Upon successful authentication, a long-lived session cookie — primarily `_canvas_middle_session` — is written to the `canvas.tongji.edu.cn` origin. This token remains valid indefinitely (no server-side expiry has been observed in practice), requiring acquisition only once per account.

Attendance is recorded by performing a GET request to:

```
https://canvas.tongji.edu.cn/lms/mobile/forscan?courseCode=<CODE>&rollCallToken=<TOKEN>
```

with the session cookie in the `Cookie` request header. A response body containing `签到成功` (success) or `已签过` (already signed) is treated as a successful outcome; a redirect to the IAM login page indicates session expiry.

---

## Building

### Requirements

| | |
|---|---|
| Xcode | 15.0+ |
| iOS Deployment Target | 17.0 |
| Swift | 6.0 |
| Third-party dependencies | None |

### Steps

```bash
git clone git@github.com:yzxoi/tongji-canvas-iOS.git
cd tongji-canvas-iOS

# Regenerate the Xcode project from the xcodegen spec (optional — project.pbxproj is committed)
brew install xcodegen
xcodegen generate

open TongJiCanvas.xcodeproj
```

Select a simulator or connected device, configure a signing team under *Signing & Capabilities*, then build and run.

### Required Permissions

| Key | Purpose |
|---|---|
| `NSCameraUsageDescription` | QR code scanning via `AVCaptureSession` |

---

## Related Projects

- [Android client](https://github.com/mmmlllnnn/TongJi_Canvas) — reference implementation in Kotlin + Jetpack Compose
- [Web client](https://github.com/mmmlllnnn/TongJi_Canvas_Web) — browser-based variant, no installation required
