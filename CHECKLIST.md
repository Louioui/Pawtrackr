# Pawtrackr Enterprise Protocol — Honest Status

Status legend: DONE = implemented, wired in, builds. SCAFFOLD = file exists but
has zero call sites (not integrated). PENDING = not started. NEEDS-DEVICE =
code can be written here but correctness can only be verified on real hardware /
a configured CloudKit environment.

## Initial baseline

- DONE — 25 SwiftData models relocated `Models/` -> `Core/Storage/Models/`.
  Project uses Xcode file-system-synchronized groups, so the move compiles
  with no pbxproj edits per file. Build verified green (iPhone 16 Pro sim).
- Modified utilities/views from the prior session are included because the
  build passes with them; their diffs have NOT been individually reviewed.

## Correction notice

A prior automated session ticked 8 boxes as "done." On audit, each was a
20-50 line stub with no call sites — none were integrated. Three were removed
because their names lied about their behavior:
- `SecurityVault.encryptSensitiveValue` returned `value.data(using: .utf8)` —
  a UTF-8 cast, not encryption. Deleted (would give a false sense of security).
- `MigrationManager.performMigration` only logged. Deleted.
- `EcosystemSyncCoordinator.forceInstantDatabaseRefresh` set a flag and slept;
  it never called `processPendingChanges()`. Deleted.

All prior-session scaffolds have been resolved — none remain in the tree.

Deleted as redundant duplicates of existing, working code:
`RevenueActor`/`BackgroundAnalyticsJanitor` (P4 — duplicated `InsightsActor` /
`DataPruner`); `UnifiedNavigationStack`/`NavigationPlaceholders` (P5 —
`ContentView` already does the adaptive TabView/NavigationSplitView layout);
`TransactionQueueService`/`PendingTransaction` (P16 — duplicated
`OfflineMutationBuffer`; `PendingTransaction` was also a CloudKit `.unique` landmine).

Also removed during P20: `GroomingWorkflow` — a dead `@Model` not in
`PawtrackrSchema.models`, carrying `@Attribute(.unique)` which CloudKit-backed
SwiftData rejects. Inert today, but a launch-crash landmine if ever schema-registered.

## 20-paragraph triage

- P2  Feature-driven directory layout ......... DONE (App/ Core/ Features/ UI/; 173 files relocated)
- P3  Move blocking work off main thread ...... DONE (already satisfied — heavy work runs off-main:
                                                InsightsActor (@ModelActor), DataStoreService.fetchAsync
                                                detached fetches, CheckoutTransactionActor, RootView
                                                Task.detached startup maintenance. True frame-stall
                                                profiling needs Instruments on-device. The protocol's
                                                "UIHierarchy X-Ray" tool does not exist.)
- P4  Background @ModelActors ................. DONE (already satisfied — InsightsActor is a
                                                @ModelActor doing revenue/analytics off-main;
                                                CheckoutTransactionActor, SyncConflictActor,
                                                DataStoreService.fetchAsync round it out. The
                                                prior session's RevenueActor/BackgroundAnalyticsJanitor
                                                were unused duplicates and were deleted.)
- P5  Adaptive iPhone/iPad/Mac layout ......... DONE (already implemented — ContentView branches on
                                                horizontalSizeClass: TabView for compact iPhone,
                                                NavigationSplitView for iPad/macOS. Prior session's
                                                UnifiedNavigationStack scaffold was redundant.)
- P6  macOS glassmorphic window styling ....... DONE (already implemented — PawtrackrApp uses
                                                .windowStyle(.hiddenTitleBar) + .windowToolbarStyle
                                                (.unified); MacTranslucentBackground wraps
                                                NSVisualEffectView; .onHover effects present.)
- P7  Keyboard shortcuts (Cmd-N/I/F) .......... DONE (already implemented — PawtrackrApp.swift
                                                macOS .commands: Cmd-N new-client sheet, Cmd-I
                                                insights, Cmd-F clients list. Cmd-F navigates to the
                                                search-equipped Clients view; SwiftUI .searchable
                                                cannot be given text-cursor focus programmatically
                                                without a fragile hack, so that nuance is left as-is.)
- P8  Localizable.xcstrings en/es ............. SKIPPED (owner decision) — app is already fully
                                                localized in English + Spanish via .strings/
                                                .stringsdict (792 NSLocalizedString calls). Migrating
                                                to the .xcstrings String Catalog is a large format
                                                change with low functional payoff. Deferred.
- P9  Decimal-only money ...................... DONE (audited: all model money fields are Decimal;
                                                no Double/Float currency math; Decimal+Money.swift
                                                uses banker's rounding. No changes needed.)
- P10 Timer Date() anchor + local ticking ..... DONE (already implemented — Visit.startedAt is the
                                                synced absolute Date anchor; VisitTimer derives
                                                elapsed from absolute dates and ticks locally,
                                                surviving background/foreground. Matches the spec.)
- P11 Micro-animations / numericText .......... LARGELY DONE (already implemented — .contentTransition
                                                (.numericText()) currency odometer in 4 views, spring
                                                curves, MotionSystem/HeroAnimation. MeshGradient — now
                                                unblocked by the iOS 18 bump — not confirmed present.)
- P12 Per-property merge timestamps ........... SKIPPED (owner decision) — a schema-breaking change
                                                to a shipped CloudKit store; data-migration risk too
                                                high to ship unverified. Deferred.
- P13 NSPersistentStoreRemoteChange observer .. DONE (already implemented — CloudKitMonitor observes
                                                .NSPersistentStoreRemoteChange, publishes
                                                .refreshRequired through the event bus, then
                                                reconciles after import. This is the real "no ghost
                                                views" mechanism; the prior session's no-op
                                                EcosystemSyncCoordinator was deleted.)
- P14 CloudKit shared zones / CKShare ......... INFEASIBLE here (needs Apple Developer portal,
                                                entitlements, multi-device; also conflicts with
                                                the single-shared-Apple-ID premise in P1)
- P15 NSUbiquitousKeyValueStore settings ...... DONE — UbiquitousSettingsStore mirrors shop-wide
                                                identity (business name, currency symbol, brand
                                                color) through iCloud KVS; observes
                                                didChangeExternallyNotification; per-device prefs
                                                (appearance, haptics, lock) deliberately excluded.
                                                KVS entitlement already present. NEEDS-DEVICE:
                                                cross-device propagation needs 2 devices / 1 iCloud.
- P16 Offline transaction buffer .............. DONE (already implemented — OfflineMutationBuffer:
                                                a bounded (240-cap) JSON-backed mutation queue with a
                                                40-record batchLimit and changedKeys; wired into
                                                CloudKitMonitor. Prior session's TransactionQueueService/
                                                PendingTransaction were redundant duplicates, deleted.)
- P17 Batched sync dispatch (40/batch) ........ DONE (already implemented — CloudKitMonitor.
                                                flushOfflineMutationBuffer drains the buffer in
                                                40-record batches with a cancellable inter-batch
                                                pause. Matches the protocol's batching intent.)
- P18 CloudKit field encryption ............... SKIPPED (owner decision) — switching existing model
                                                fields to @Attribute(.allowsCloudEncryption) is a
                                                schema-breaking change on a shipped CloudKit store.
                                                Deferred.
- P19 Encryption-key-reset recovery ........... N/A while P18 is unimplemented —
                                                CKErrorUserDidResetEncryptedDataKey can only fire for
                                                encrypted fields, and the app has none. Should ship
                                                with P18. Note: the protocol's prescription (manually
                                                deleting the CloudKit zone) would corrupt
                                                NSPersistentCloudKitContainer's automatic mirroring;
                                                correct recovery is detection + surfacing.
- P20 @Attribute(.externalStorage) ............ DONE (already on every binary field: Client/Pet
                                                photo+thumbnail, Visit before/after photo+thumbnail,
                                                BusinessConfig logo. CheckoutDraft is JSON-persisted,
                                                not a SwiftData model, so externalStorage is N/A.)
- P20 #Index compound indexes ................. DONE — deployment target raised to iOS 18 /
                                                macOS 15 (owner-approved); #Index added to Visit,
                                                Client, Pet, DaySummary, CheckoutTransaction; schema
                                                bumped to 1.0.4 (additive/lightweight). NEEDS-DEVICE:
                                                confirm the index migration runs cleanly against a
                                                live CloudKit-backed store.

## Summary

Resolved: 14 of 20 paragraphs (P1 is the intro, not a task).
- New work this pass: P2 (structure), P15 (iCloud KV settings), P20 (iOS 18 + #Index).
- Verified already-implemented in this mature codebase: P3, P4, P5, P6, P7, P9,
  P10, P11, P13, P16, P17.
- Owner-skipped: P8 (already localized), P12 + P18 (schema-breaking, unverifiable).
- P14 infeasible here; P19 N/A until P18 ships.

## Test status

- Build: green on both iOS (iPhone 16 Pro sim) and macOS.
- Unit tests: 228 passed, 0 failures.
- UI tests: 4 failures — testActiveSessionDisappearsAfterCheckoutCompletes,
  testCheckoutManualAmountEntry, testChangePINSheetOpensWithThreeFields,
  testExportClientsButtonOpensSharePreviewSheet. These are PRE-EXISTING: they
  fail identically at commit d26cf1e (before this session and before the prior
  megaprompt session), so this session's work did not introduce them. They are
  the app's own UI-test debt — out of scope for the protocol work, flagged for
  a separate fix pass.

## Cannot be verified from this environment

P13/P15/P16/P17 are implemented and compile, but their cross-device behavior
(remote-change propagation, offline-buffer drain, KVS sync) can only be proven
with 2+ physical devices on one iCloud account. P20's index migration needs a
live CloudKit-backed store to confirm. P14 needs an Apple Developer portal
with CloudKit sharing configured.
