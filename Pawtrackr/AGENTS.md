# Pawtrackr AGENTS.md
## The "God-Tier" Golden Rules

### 1. Persistence & Sync (iCloud Sovereignty)
- **Main Thread is Holy:** UI updates only. All ModelContext.save() and database operations MUST occur within a `ModelActor`.
- **Decimal for Money/Weight:** Never use `Double` or `Float`. Always use `Decimal` for precision.
- **Atomicity:** All multi-model operations (e.g., Checkout) must be atomic. No intermediate states allowed.
- **Conflict Resolution:** Use Field-Wise Reconciliation, never "Last-Writer-Wins".

### 2. Logging & Forensics
- **Unified Logging (OSLog):** No `print()`. Use `Logger.ui`, `.performance`, `.database`, `.network`, or `.security`.
- **Telemetry:** If a sync failure occurs, log with `.error` and trigger a non-intrusive alert.

### 3. UI & Motion
- **Interactive Feedback:** All buttons must use `pressScaleStyle()`. Use `DS.Motion.animation` for consistency.
- **Accessibility (A11y):** All interactive elements must have `accessibilityLabel`. Support Dynamic Type by using flexible stacks.
- **Privacy:** All Insights/Revenue screens must use `.privacyBlur()` to protect business data in the background.

### 4. Performance
- **Data Pruning:** Maintain the `DataPruningService` to purge assets older than 30 days.
- **O(1) Data Access:** Refactor all lists and dashboard calculations to O(1) or O(log n) using `PersistentIdentifier` lookups.

### 5. Architectural Integrity
- **Fail Gracefully:** CloudKit down? Show the schedule in Read-Only mode. Do not crash.
- **Native Primitives:** Prefer Apple-native frameworks (Charts, PhotosUI) over custom utility code.
- **Documentation:** Every new utility function must contain DocC-style comments.
