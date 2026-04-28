# Canvas Session Multiplexer

*A Concurrent Per-User HTTP Proxy for LMS Attendance*

[![CI](https://github.com/yzxoi/tongji-canvas-iOS/actions/workflows/ci.yml/badge.svg)](https://github.com/yzxoi/tongji-canvas-iOS/actions/workflows/ci.yml)
[![Swift](https://img.shields.io/badge/Swift-6.0-FA7343?logo=swift)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-17.0%2B-7C3AED?logo=apple)](https://developer.apple.com/ios)
[![Xcode](https://img.shields.io/badge/Xcode-16.0%2B-147EFB?logo=xcode)](https://developer.apple.com/xcode)
[![Platform](https://img.shields.io/badge/Platform-iOS-lightgrey?logo=apple)](https://developer.apple.com/ios)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)

---

## Abstract

This project investigates a practical concurrency problem in HTTP client design: **how to fan out authenticated requests to a single origin while maintaining per-identity cookie isolation, without serialising through shared mutable state.**

The Tongji University Canvas LMS exposes an attendance endpoint (`/lms/mobile/forscan`) that identifies the submitter solely by a session cookie (`_canvas_middle_session`). Submitting attendance for *N* accounts therefore requires *N* authenticated HTTP GET requests, each carrying a distinct cookie — a textbook fan-out pattern that conventional HTTP client architecture handles poorly.

The reference Android implementation (`TongJi_Canvas`) works around Android's process-wide `CookieManager` by serialising per-user requests: flush → set → send → repeat. Correct, but O(N) in wall time.

This project explores an alternative: **use ephemeral `URLSession` instances configured to bypass shared cookie storage entirely**, injecting credentials as explicit `Cookie` headers per request. The result is true task-level parallelism under Swift 6 structured concurrency — all *N* accounts sign concurrently in O(1) wall time, bounded only by the server's connection limits.

Built for research, testing, and educational purposes.

---

## Experimental Setup

### Problem Statement

```
                ┌──────────────────────────────┐
                │  canvas.tongji.edu.cn         │
                │  GET /lms/mobile/forscan?...  │
                │  ── identifies user by Cookie │
                └──────────┬───────────────────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
           User A       User B       User C
        (cookie_a)    (cookie_b)    (cookie_c)

   Naive approach: shared Cookie jar → data race
   Serial approach:  sequential requests → O(N) time
   Our approach:     isolated per-request headers → O(1) time
```

### Hypothesis

Per-request `Cookie` header injection with `URLSessionConfiguration.ephemeral` (no shared cookie store) can achieve the same correctness guarantee as serial execution while exploiting HTTP connection reuse for latency comparable to a single request.

### Variables

| Variable | Control (Android) | Experiment (iOS) |
|---|---|---|
| Cookie storage | `CookieManager` (process singleton) | None (`httpShouldSetCookies = false`) |
| Credential injection | Per-session `CookieManager` mutation | Per-request `Cookie` header |
| Concurrency model | Sequential (`for` loop) | Structured (`withTaskGroup`) |
| Actor isolation | None (manual serialisation) | `@MainActor` + `nonisolated` network path |
| Connection reuse | Implicit | Explicit (`static let urlSession`) |

---

## Architecture

```
TongJiCanvas/
├── Models/
│   ├── UserSession.swift          # Value type; accessToken excluded from CodingKeys
│   └── Course.swift               # Course group model
├── Data/
│   └── SessionRepository.swift    # @MainActor ObservableObject; Keychain-backed persistence
├── Extensions/
│   └── Color+Hex.swift
├── Utils/
│   ├── CookieHelper.swift         # Cookie string ↔ HTTPCookie conversion
│   └── KeychainHelper.swift       # SecItem wrapper; kSecAttrAccessibleWhenUnlockedThisDeviceOnly
├── Components/
│   ├── WebView.swift              # WKWebView UIViewRepresentable
│   └── SessionCard.swift          # Reusable account card
└── Views/
    ├── MainView.swift             # Account list, course groups, toolbar
    ├── LoginView.swift            # IAM OAuth2 WebView shell
    ├── LoginViewModel.swift       # Cookie capture state machine + countdown
    ├── ManualAddView.swift        # Raw cookie import
    ├── EditSessionView.swift      # Account editor
    ├── AddCourseView.swift        # Course creation
    ├── EditCourseView.swift       # Course membership editor
    ├── ScannerView.swift          # AVFoundation QR scanner
    ├── BatchSignView.swift        # Fan-out progress UI
    └── AboutView.swift            # Credits and links
TongJiCanvasTests/
├── BatchSignViewModelTests.swift  # State machine coverage
├── CookieHelperTests.swift        # Parsing edge cases
├── UserSessionTests.swift         # Codable invariants
├── SessionRepositoryTests.swift   # CRUD + Keychain persistence
└── KeychainHelperTests.swift      # SecItem correctness
```

### Session Isolation Design

```swift
// Each request is an independent HTTP transaction.
// No shared Cookie jar. No cross-account state.

static let urlSession: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.httpShouldSetCookies = false       // never write to shared store
    config.httpCookieAcceptPolicy = .never    // never read from shared store
    config.httpMaximumConnectionsPerHost = 8  // reuse TCP for fan-out
    return URLSession(configuration: config)
}()

// Cookie injected per-request, not per-session
request.setValue(cookieValue, forHTTPHeaderField: "Cookie")
```

### Concurrency Model

```swift
@MainActor
final class BatchSignViewModel: ObservableObject {

    // Network path: off-actor, true parallel execution
    private nonisolated static func performSign(
        url: URL, cookieValue: String
    ) async -> SignResult { ... }

    // Coordination: on-actor, sequential by design
    private func signAll() async {
        await withTaskGroup(of: Void.self) { group in
            for session in sessions {
                group.addTask { [weak self] in
                    await self?.sign(session: session)
                }
            }
        }
    }
}
```

The `nonisolated static` network path runs on Swift's cooperative thread pool. Status updates (`@Published` mutations) are dispatched back to `@MainActor`. This separation ensures:

1. **Network I/O never blocks the main thread.**
2. **Status updates are data-race–free.** (All `@Published` writes happen on `@MainActor`.)
3. **Connection reuse persists across sign-in rounds.** (`static let urlSession` outlives individual ViewModel instances.)

### Credential Lifecycle

```
User logs in (WKWebView)
       │
       ▼
WKHTTPCookieStoreObserver detects _canvas_middle_session
       │
       ▼
Cookie string captured via CookieHelper.captureCanvasCookies()
       │
       ▼
Stored in Keychain (kSecClassGenericPassword, scoped to session UUID)
       │  ┌─ UserDefaults: displayName, UUID, course membership (metadata only)
       │  └─ Keychain:      accessToken (sensitive)
       ▼
At sign-in time: KeychainHelper.read(key: sessionId) → Cookie header on URLRequest
```

---

## Test Suite

48 tests across 5 suites, all passing under Swift Testing with `ENABLE_TESTABILITY = YES`.

| Suite | Count | Coverage |
|---|---|---|
| `BatchSignViewModelTests` | 13 | Progress computation, counts, `hasActiveSigning`, `toggleExpanded`, `SignStatus` labels/icons |
| `CookieHelperTests` | 9 | Single/multiple/empty/equals-in-value parsing, custom domain, real-world cookie string |
| `UserSessionTests` | 5 | UUID generation, `hasCredentials`, Codable round-trip (token exclusion verified), `Equatable` |
| `SessionRepositoryTests` | 16 | Full CRUD, Keychain survival across repo reload, nil-token clears Keychain, import/export round-trip, `selectedIds` persistence |
| `KeychainHelperTests` | 7 | `SecItemAdd`/`CopyMatching`/`Delete`, overwrite, empty value, special characters, `deleteAll` |

`SessionRepositoryTests` is annotated `@Suite(.serialized)` to prevent concurrent `UserDefaults` mutation. `KeychainHelperTests` uses per-case UUID-scoped keys for full concurrency safety.

---

## Build & Run

```bash
# Prerequisites
brew install xcodegen

# Generate Xcode project
xcodegen generate

# Open in Xcode
open TongJiCanvas.xcodeproj

# Run tests
xcodebuild test -scheme TongJiCanvas -destination 'platform=iOS Simulator,name=iPhone 16'
```

### Requirements

| Item | Version |
|---|---|
| Xcode | 16.0+ |
| iOS Deployment Target | 17.0 |
| Swift | 6.0 |
| Dependencies | None |

---

## Related Work

| Project | Platform | Concurrency Strategy |
|---|---|---|
| [TongJi_Canvas](https://github.com/mmmlllnnn/TongJi_Canvas) | Android (Kotlin) | Sequential `CookieManager` mutation |
| [TongJi_Canvas_Web](https://github.com/mmmlllnnn/TongJi_Canvas_Web) | Web (JS) | Single-user, URL-param–based |
| **This project** | iOS (Swift 6) | Per-request header injection + `withTaskGroup` fan-out |

---

## Acknowledgements

The Android and Web reference implementations by [mmmlllnnn](https://github.com/mmmlllnnn) provided the initial problem analysis and endpoint documentation. This iOS port explores the same problem space under a different set of platform constraints and concurrency primitives.

Built as an experiment in structured concurrency, HTTP client isolation, and credential storage patterns on Apple platforms.

---

## License

This project is provided for educational and research purposes.
