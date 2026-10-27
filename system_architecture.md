# Architecture & Design Specification: Keyboard-First macOS Email Client

## 1. System Architecture Overview

The application follows a **Local-First, Optimistic UI Architecture**. The UI layer interacts *only* with the local SQLite storage engine. Network operations execute asynchronously via an out-of-band background synchronizer.

```
+-----------------------------------------------------------------+
|                         SwiftUI Layer                           |
|  (Views, Key Event Handling, Command Palette, Focus State)      |
+-------------------------------+---------------------------------+
                                | Reads / User Actions
                                v
+-----------------------------------------------------------------+
|                       Local Data Layer                          |
|     (GRDB / SQLite DB - Accounts, Emails, Threads, SyncQueue)   |
+-------------------------------+---------------------------------+
                                | Asynchronous Queue Processing
                                v
+-----------------------------------------------------------------+
|                   Background Sync Engine                       |
|   (SyncQueueManager -> Gmail REST API -> Keychain Credentials)  |
+-----------------------------------------------------------------+
```

---

## 2. Tech Stack Specifications

- **OS Target:** macOS 14.0+ (Sonoma or newer)
- **Language & UI:** Swift 5.9+ with SwiftUI (using AppKit `NSEvent` monitors where fine-grained global key intercept is required)
- **Database Engine:** `GRDB.swift` (SQLite wrapper for thread-safe concurrent reads/writes)
- **Authentication:** `ASWebAuthenticationSession` (OAuth 2.0 with Gmail API scopes)
- **Credential Storage:** macOS Keychain via Swift Security framework wrappers

---

## 3. Data Schema & Models (`GRDB.swift`)

### Account Table
```sql
CREATE TABLE account (
    id TEXT PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    avatar_url TEXT,
    created_at INTEGER NOT NULL
);
```

### Email Table
```sql
CREATE TABLE email (
    id TEXT PRIMARY KEY,
    thread_id TEXT NOT NULL,
    account_id TEXT NOT NULL,
    sender_name TEXT NOT NULL,
    sender_email TEXT NOT NULL,
    recipient_emails TEXT NOT NULL, -- Stored as comma-separated or JSON string
    subject TEXT NOT NULL,
    snippet TEXT,
    body_html TEXT,
    body_text TEXT,
    received_at INTEGER NOT NULL,
    is_read BOOLEAN NOT NULL DEFAULT 0,
    is_archived BOOLEAN NOT NULL DEFAULT 0,
    is_starred BOOLEAN NOT NULL DEFAULT 0,
    category TEXT NOT NULL CHECK (category IN ('important', 'newsletters', 'promotions', 'spam')),
    FOREIGN KEY(account_id) REFERENCES account(id) ON DELETE CASCADE
);

CREATE INDEX idx_email_account_category ON email(account_id, category, is_archived, received_at DESC);
CREATE INDEX idx_email_thread ON email(thread_id);
```

### SyncQueue Table
```sql
CREATE TABLE sync_queue (
    id TEXT PRIMARY KEY,
    account_id TEXT NOT NULL,
    action_type TEXT NOT NULL CHECK (action_type IN ('archive', 'delete', 'mark_read', 'move')),
    target_email_id TEXT NOT NULL,
    payload TEXT, -- JSON string for extra data (e.g., target folder label)
    status TEXT NOT NULL CHECK (status IN ('pending', 'processing', 'failed')),
    retry_count INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL
);
```

---

## 4. Core Component Responsibilities

### A. UI & Event Handler (`KeyboardManager`)
- Intercepts key strokes (`j`, `k`, `e`, `#`, `Cmd+K`) before standard view routing.
- Mutates local View Models immediately and triggers SQLite updates.

### B. Categorization Engine (`EmailCategorizer`)
- Analyzes incoming message headers during background fetch:
  - If `List-Unsubscribe` header exists $\rightarrow$ `newsletters`
  - If sender email matches `no-reply@`, `news@`, `notifications@` $\rightarrow$ `newsletters`
  - If bulk/marketing headers exist $\rightarrow$ `promotions`
  - Otherwise, assign to `important`.

### C. Sync Queue Manager (`SyncQueueManager`)
- Continuously listens to `sync_queue` records in SQLite.
- Executes HTTP REST calls to Gmail API (`messages.batchModify` or `messages.delete`).
- Implements exponential backoff on network failures.

---

## 5. Development Milestones & Checklist

- [ ] **Phase 1 (v0.1 - Core Local Flow):**
  - Set up SQLite schema with GRDB.
  - Implement mock email generator.
  - Build main split view UI (Sidebar, Thread List, Detail Reader).
  - Implement `j`/`k` list selection and instant `e` (archive) UI updates.

- [ ] **Phase 2 (v0.2 - Command Palette & Keybindings):**
  - Build floating Command Palette modal with fuzzy search.
  - Bind global keyboard shortcuts (`Cmd+K`, `1/2/3`, `r`, `c`).

- [ ] **Phase 3 (v0.3 - Auth & Real Sync Engine):**
  - Add OAuth2 auth flow for Gmail.
  - Build initial sync loop (`messages.list` & `messages.get`).
  - Wire up `SyncQueueManager` to execute remote mutations.