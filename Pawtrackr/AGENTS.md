# Pawtrackr AGENTS.md
## The "God-Tier" Golden Rules

### 1. Local Persistence
- **Main Thread is Holy:** UI updates only. All ModelContext.save() and database operations MUST occur within a `ModelActor`.
- **Decimal for Money/Weight:** Never use `Double` or `Float`. Always use `Decimal` for precision.
- **Atomicity:** All multi-model operations (e.g., Checkout) must be atomic. No intermediate states allowed.
- **Local Storage Only:** Configure every persistent store with `cloudKitDatabase: .none`. Do not add cloud permissions, remote sync engines, device presence, or cloud-backed settings.
- **Store Compatibility:** Retain shipped model types and fields, including legacy metadata. Keep store changes additive and preserve the existing named store URL.
- **Conflict Resolution:** Preserve unrelated fields when saving edits from another local context.

### 2. Logging & Forensics
- **Unified Logging (OSLog):** No `print()`. Use `Logger.ui`, `.performance`, `.database`, `.network`, or `.security`.
- **Telemetry:** Log local persistence failures with `.error` and surface the failed operation in the UI.

### 3. UI & Motion
- **Interactive Feedback:** All buttons must use `pressScaleStyle()`. Use `DS.Motion.animation` for consistency.
- **Accessibility (A11y):** All interactive elements must have `accessibilityLabel`. Support Dynamic Type by using flexible stacks.
- **Privacy:** All Insights/Revenue screens must use `.privacyBlur()` to protect business data in the background.

### 4. Performance
- **Data Pruning:** Maintain the `DataPruningService` to purge assets older than 30 days.
- **O(1) Data Access:** Refactor all lists and dashboard calculations to O(1) or O(log n) using `PersistentIdentifier` lookups.

### 5. Architectural Integrity
- **Fail Gracefully:** If local storage fails to open, show recovery with preserved backups. Never delete the store or promise remote recovery.
- **Native Primitives:** Prefer Apple-native frameworks (Charts, PhotosUI) over custom utility code.
- **Documentation:** Every new utility function must contain DocC-style comments.
