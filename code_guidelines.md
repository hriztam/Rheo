# Engineering & Code Guidelines: Rheo (macOS Email Client)

## 1. Core Engineering Philosophy
Rheo is engineered as a high-performance, keyboard-first, native macOS email client. Code quality must mirror the highest standards expected in senior macOS / Apple platforms development:
1. **Local-First, Sub-50ms Latency**: The user interface interacts strictly with the local SQLite / GRDB store. Network operations must never block the main thread or user interactions.
2. **Predictable Concurrency & Swift 6 Readiness**: Every component has a clear isolation model (`@MainActor`, dedicated `actor`, or value type `Sendable`). Avoid concurrency warnings and thread safety pitfalls.
3. **Explicit, Single-Responsibility Design**: Small, focused files and modules. No monolithic god-objects.
4. **Resilient Network & Error Handling**: Graceful degradation, typed domain errors, explicit retry/backoff policies, and non-crashing failure paths.

---

## 2. Directory & File Organization

Files must be placed according to their domain and architectural layer. Each file must declare exactly one primary type or tightly-coupled small extension.

```
Sources/
├── Core/
│   ├── Configuration/          # App config, environment loaders, constants
│   ├── Logging/                # Unified os_log / Logger wrappers
│   └── Extensions/             # Reusable Foundation / Swift standard library extensions
├── Models/
│   ├── Entities/               # GRDB persistent domain models (Account, Email, SyncQueueItem)
│   ├── ValueObjects/           # Enums, Identifiers, Domain types (EmailCategory, SyncActionType)
│   └── DTOs/                   # Network & API transfer objects (GmailMessage, ProfileResponse)
├── Network/
│   ├── OAuth/                  # OAuth2 client, PKCE, loopback server, auth contracts
│   ├── Security/               # Keychain storage services and secure token caching
│   └── Gmail/                  # Gmail REST API clients, endpoint builders, network errors
├── Database/
│   ├── Migrations/             # Database migrators and versioned schema definitions
│   ├── Repositories/           # Data access objects (AccountRepository, EmailRepository)
│   └── DatabaseManager.swift   # Database connection pool / queue management
├── Categorization/             # Heuristics & rule engines for smart email classification
├── Sync/                       # Background synchronizer, queue processors, mutation workers
└── UI/
    ├── DesignSystem/           # Typography, tokens, colors, reusable UI components
    ├── Keyboard/               # NSEvent monitors, keybindings, shortcut coordinator
    ├── Navigation/             # Window routing, command palette, modal sheets
    └── Views/                  # Feature views and corresponding @MainActor ViewModels
```

---

## 3. Naming Conventions

Follow Apple's official [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).

### A. File Naming
- **Single Type per File**: Filename must exactly match the primary type declared inside:
  - `OAuthManager.swift` contains `final class OAuthManager` or `actor OAuthManager`.
  - `EmailListView.swift` contains `struct EmailListView: View`.
  - `AccountRepository.swift` contains `actor AccountRepository` or `protocol AccountRepository`.
- **Extensions**: Name files containing extensions after the type and extended functionality:
  - `Data+Base64URL.swift`
  - `Date+RelativeFormatting.swift`
- **PascalCase**: Always use PascalCase for Swift source files. Never use kebab-case (`oauth-manager.swift`) or snake_case (`oauth_manager.swift`).

### B. Types & Protocols
- **Protocols describing capabilities**: Suffix with `-able`, `-ible`, or `-ing` (e.g., `CredentialStore`, `EmailSyncing`, `JSONPayloadDecodable`).
- **Protocols describing identity/type**: Plain nouns (e.g., `OAuthProvider`, `MailClient`).
- **Enums & Structs & Actors**: Descriptive singular nouns (`EmailCategory`, `KeychainManager`, `SyncQueueItem`).

### C. Functions & Variables
- **Clarity over brevity**: Favor readability over short cryptic acronyms.
  - Good: `fetchInboxEmails(forAccountId:category:)`
  - Bad: `getMsgs(accId:cat:)`
- **Naming Mutating / Non-mutating methods**: Follow Swift conventions (`sort()` vs `sorted()`, `filter()` vs `filtered()`).
- **Boolean properties**: Should read as assertions: `isArchived`, `hasUnreadMessages`, `canPerformSync`.

---

## 4. Architecture & Separation of Concerns

### A. Authentication & Network Boundary
- **Separation of Concerns**:
  - `OAuthManager`: Solely responsible for authentication flow (PKCE authorization URL creation, loopback callback capture, token exchange, and refresh).
  - `KeychainManager`: Solely responsible for storing and querying sensitive credentials in the macOS Keychain. Must not contain HTTP logic.
  - `GmailAPIClient`: Consumes access tokens to perform authenticated API queries. It must not handle OAuth browser windows or UI presentation.
- **Token Freshness**: Network layers or sync workers obtain valid tokens via a coordinating credential provider that automatically refreshes expiring access tokens.

### B. Local-First Database Layer
- **Optimistic UI Principle**: All UI operations modify the local SQLite database first via dedicated repository methods.
- **Background Sync Queue**: Mutations (archive, delete, mark read, label updates) insert a corresponding task record into `sync_queue`. The `SyncEngine` drains this queue asynchronously.
- **Concurrency Isolation**: Database operations must be actor-isolated (`DatabaseManager` or dedicated repositories) to prevent data races and lock contention.

### C. UI & ViewModels
- All ViewModels must be annotated with `@MainActor`.
- Views should remain declarative and thin. Complex state mutation, database writes, and queue scheduling belong in ViewModels or dedicated Services.
- Avoid passing raw database actors deep into leaf views. Pass models or observable view states.

---

## 5. Swift Concurrency & Code Standards

### A. Swift 6 Concurrency Compliance
- Do not access actor-isolated state from synchronous, nonisolated initializers.
- Store mutable state inside `actor` or `@MainActor` types.
- Ensure all asynchronous models passed across actor boundaries conform to `Sendable`.
- Avoid unsafe `nonisolated(unsafe)` workarounds unless integrating with legacy C/Objective-C APIs with strict locks.

### B. Clean Functions & Readability
- **Function Size**: Functions should ideally be under 40 lines. Break large functions with multiple responsibilities into private helper functions with clear intent.
- **Guard Clauses**: Use early `guard` returns to minimize nesting levels.
- **Inline Comments**: Include concise one-line comments explaining *why* a particular non-obvious logic or boundary condition exists (e.g., handling URL-safe Base64 padding for Gmail payloads).
- **No Force Unwrapping**: Avoid `!` force-unwrapping and `try!` in production logic. Always handle optionality and errors explicitly with typed error propagation.

---

## 6. Error Handling & Logging

### A. Domain Errors
Define dedicated domain error enums conforming to `LocalizedError`:
```swift
enum OAuthError: LocalizedError {
    case missingClientID
    case authorizationDenied(reason: String)
    case tokenExchangeFailed(statusCode: Int, message: String?)

    var errorDescription: String? { ... }
}
```
Include context (status codes, response bodies, underlying errors) to make diagnostics actionable.

### B. Logging
- Use Apple's unified logging (`os.Logger`) rather than generic `print` statements:
```swift
import os

enum AppLog {
    static let auth = Logger(subsystem: "com.rheo.mail", category: "Auth")
    static let sync = Logger(subsystem: "com.rheo.mail", category: "Sync")
    static let database = Logger(subsystem: "com.rheo.mail", category: "Database")
}
```
- Never log user email bodies, tokens, or private OAuth secrets.

---

## 7. Configuration & Secrets Management

- Secrets (such as `GMAIL_CLIENT_ID` and optional `GMAIL_CLIENT_SECRET`) must never be hardcoded into source files.
- Development credentials should be loaded from:
  1. Process Environment Variables (`ProcessInfo.processInfo.environment`).
  2. Local `.env` file (strictly excluded via `.gitignore`).
  3. App Bundle `Info.plist` (in production release bundles).
- Provide `.env.example` with documented keys for new developer setup.
