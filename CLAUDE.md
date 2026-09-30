# Pawtrackr Architecture Memory

## Checkout Pilot Decisions

- `CheckoutViewModel` is the only owner of checkout UI state. `CheckoutView` can bind to editor buffers, but every persisted value must flow back through the view model before navigation or confirmation.
- Checkout money is Decimal-only. Service subtotal, manual amount overrides, payments, and line-item reconciliation must avoid `Double` currency math.
- Checkout takes no tips: the total is the selected services or the amount typed over them. `CheckoutDraft` keeps its tip fields so older drafts still decode, but restore ignores them.
- The 4-step checkout draft is a crash-recovery boundary. Step transitions, payment method changes, and external references are critical state and must be saved immediately through `CheckoutDraftStore`.
- Draft disk I/O belongs off the main actor. `CheckoutDraftStore` remains an actor for serialization, while JSON/file reads and writes execute through detached utility tasks.
- Confirm-and-pay is protected at two layers: a UI/view-model debounce blocks rapid duplicate taps, and `CheckoutTransactionActor` keeps persistence idempotent by visit UUID.
- Checkout success must not hide cleanup or refresh failures. Draft deletion and main-context refresh errors are logged instead of swallowed with `try?`.

## Data Store Pilot Decisions

- `DataStoreService` is the central SwiftData access facade. The production initializer accepts an existing `ModelContainer`; test and QualityControl code can use the `inMemory` initializer.
- Background fetches must create a detached `ModelContext` from the shared `ModelContainer`; UI-bound fetches remain on the main actor.
- The store opens WITHOUT a SwiftData `SchemaMigrationPlan` (ADR-0004). 1.0.2 shipped a staged plan built from live model classes, every 1.0.1 store failed with 134504, and users reset their clients away. Keep model changes additive (new models, optional/defaulted properties, `@Attribute(originalName:)` renames); CI fails if `migrationPlan:` reappears.
- Every release adds its store to `PawtrackrTests/Fixtures` (see `StoreFixtures.md`); `StoreUpgradeRegressionTests` must open all of them. Before shipping, install the previous App Store build, add data, then install the new build over it without deleting.
- Store-file work (scheduled restore, per-build backup, legacy move) runs only in `PawtrackrApp.init`, before any container opens. Nothing deletes a store: resets and restores move files into `RecoveryBackup-*` / `PreRestoreBackup-*`, which `StoreBackupRestore` can bring back.
- `DataStoreRecoveryView` must never make a destructive action the primary one or promise that iCloud will restore data.

## Verification Notes

- Don't assume a simulator destination exists — resolve one first with `xcrun simctl list devices available` and pass it as `-destination "id=<UUID>"`. As of 2026-07, the installed runtimes are iOS 18.x and 26.5 (no 17.x); named-device + `OS:latest` lookups have failed on this machine before.
- The paywall loads live StoreKit products from `Pawtrackr.storekit` — both shared schemes reference it in their LaunchAction. If `Product.products` returns nothing in a dev build, check that scheme reference before suspecting code.
