# Pawtrackr Enterprise Protocol — Honest Status

Status legend: DONE = implemented, wired in, builds. SCAFFOLD = file exists but
has zero call sites (not integrated). PENDING = not started. NEEDS-DEVICE =
code can be written here but correctness can only be verified on real hardware /
a configured CloudKit environment.

## Baseline (this commit)

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

Remaining as SCAFFOLD (unwired, kept as honest starting points):
`RevenueActor`, `BackgroundAnalyticsJanitor`, `TransactionQueueService`,
`PendingTransaction`, `UnifiedNavigationStack`, `NavigationPlaceholders`.

Also removed during P20: `GroomingWorkflow` — a dead `@Model` not in
`PawtrackrSchema.models`, carrying `@Attribute(.unique)` which CloudKit-backed
SwiftData rejects. Inert today, but a launch-crash landmine if ever schema-registered.

## 20-paragraph triage

- P2  Feature-driven directory layout ......... DONE (App/ Core/ Features/ UI/; 173 files relocated)
- P3  Move blocking work off main thread ...... PENDING (audit needed; "X-Ray" tool is fictional)
- P4  Background @ModelActors ................. SCAFFOLD (2 of 3 exist, unwired)
- P5  Adaptive iPhone/iPad/Mac layout ......... SCAFFOLD (UnifiedNavigationStack unused)
- P6  macOS glassmorphic window styling ....... PENDING
- P7  Keyboard shortcuts (Cmd-N/I/F) .......... PENDING
- P8  Localizable.xcstrings en/es ............. PENDING (large)
- P9  Decimal-only money ...................... DONE (audited: all model money fields are Decimal;
                                                no Double/Float currency math; Decimal+Money.swift
                                                uses banker's rounding. No changes needed.)
- P10 Timer Date() anchor + local ticking ..... PENDING
- P11 Micro-animations / numericText .......... PENDING
- P12 Per-property merge timestamps ........... PENDING (schema change) / NEEDS-DEVICE to verify
- P13 NSPersistentStoreRemoteChange observer .. PENDING / NEEDS-DEVICE to verify
- P14 CloudKit shared zones / CKShare ......... INFEASIBLE here (needs Apple Developer portal,
                                                entitlements, multi-device; also conflicts with
                                                the single-shared-Apple-ID premise in P1)
- P15 NSUbiquitousKeyValueStore settings ...... PENDING
- P16 Offline transaction buffer .............. SCAFFOLD (queue exists; push step is a TODO comment)
- P17 Batched sync dispatch (40/batch) ........ PENDING / NEEDS-DEVICE to verify
- P18 CloudKit field encryption ............... PENDING (real approach: @Attribute(.encrypt) /
                                                .encryptedValues on the model, not a custom class)
- P19 Encryption-key-reset recovery ........... PENDING / NEEDS-DEVICE to verify
- P20 @Attribute(.externalStorage) ............ DONE (already on every binary field: Client/Pet
                                                photo+thumbnail, Visit before/after photo+thumbnail,
                                                BusinessConfig logo. CheckoutDraft is JSON-persisted,
                                                not a SwiftData model, so externalStorage is N/A.)
- P20 #Index compound indexes ................. BLOCKED — #Index macro requires iOS 18; project
                                                deploys to iOS 17. Raising the min OS drops iOS 17
                                                devices: a product decision for the owner. Drafted
                                                indexes (revert-on-file): Visit[startedAt|endedAt|
                                                createdAt], Client[lastName+firstName|lastVisitDate],
                                                Pet[createdAt|name], DaySummary[day],
                                                CheckoutTransaction[createdAt|visitUUID|idempotencyKey].

## Cannot be done from this environment

P14 and full verification of P12/P13/P15/P16/P17/P19 require a real Apple
Developer account, CloudKit container configuration, and 2+ physical devices
signed into iCloud. Code for these can be written here; correctness cannot be
proven from a single simulator.
