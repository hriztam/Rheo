# Context & Project Guidelines: Keyboard-First macOS Email Client

## 1. Executive Summary
This project is a high-performance, keyboard-first native macOS email client designed to eliminate email overload for users managing multiple Google accounts. Inspired by Superhuman, the app prioritizes sub-50ms UI latency, an intuitive shortcut-driven workflow, smart triage/categorization, and a robust local-first architecture.

---

## 2. Core Engineering Principles

### A. "Make It Exist First, Then Make It Better"
- **Focus on a Rock-Solid MVP (v0.1 over a buggy v2.0):** Prioritize complete end-to-end functionality for core features before adding secondary optimizations.
- **Incremental Delivery:** Build vertical slices (e.g., Local DB → UI rendering → Keyboard shortcuts → Async network queue) rather than incomplete global systems.

### B. Code Quality & Maintainability (Senior macOS Developer Standards)
- **Neat & Readable Logic:** Avoid packing complex logic or chained operations into a single line. Break down transformations into clear, step-by-step statements.
- **Self-Documenting Code:** Use descriptive variable, function, and parameter names.
- **One-Line Inline Comments:** Include a concise one-line comment above functions or complex blocks explaining *what* it does and *why*.
- **Balanced Reusability:** Write modular, reusable utilities (e.g., reusable UI primitives, generic SQLite query helpers) without over-engineering abstraction layers prematurely.

### C. Proactive Clarification & Communication
- **Ask Before Assuming:** The coding agent must proactively ask clarifying questions regarding ambiguous UI design patterns, infrastructure decisions, data models, or platform behaviors before making major implementation choices.

---

## 3. Product Features & User Workflows

### A. Keyboard-First Navigation
- **Primary Keys:**
  - `j` / `k` (or Down/Up arrow keys): Navigate up and down the thread list.
  - `e` / `y`: Archive selected thread immediately.
  - `#` / `Delete`: Trash selected thread.
  - `r`: Quick reply to current thread.
  - `c` / `n`: Open compose window.
  - `1`, `2`, `3`: Jump between split inbox categories.
  - `Cmd + K`: Open Command Palette for fuzzy searching actions and folders.

### B. Smart Triage & Categorization
- **Split Inbox Views:**
  1. **Important:** Direct communication, personal/work contacts.
  2. **Newsletters:** Automated emails, bulk updates, subscriptions (detected via headers like `List-Unsubscribe`).
  3. **Promotions:** Marketing and promotional emails.

### C. Zero-Latency Local Execution (Optimistic UI)
- All user actions instantly modify local state and database views.
- Network sync happens silently in the background via a persistent queue.

---

## 4. Coding Agent Instructions
When implementing features or refactoring:
1. Refer to `architecture.md` for strict data flow rules.
2. Ensure every file is well-structured and follows Swift best practices.
3. Keep code modular, predictable, and easy to unit test.