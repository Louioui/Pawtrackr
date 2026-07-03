# Pawtrackr iOS — Architecture Review & Decision Records

**Date:** 2026-07-03
**Reviewer:** architecture pass over `/Users/mac/Desktop/Pawtrackr` (branch `Master`, marketing version 1.0.1)
**Decider:** Luis (solo developer)
**Source request:** `newUpdatesForPawtrackr.rtf` (an updates brainstorm) + "do task for the pawtrackr iOS"

---

## What the RTF actually is

The submitted `newUpdatesForPawtrackr.rtf` is a long brainstorm transcript, not a spec. Read
literally it is **self-contradictory**, and its "conceptual" Swift diverges from the shipped
codebase. Distilled, it contains four threads:

1. **Monetization** — proposed *three incompatible ways*: a one-time **$29.99 non-consumable**
   behind a 7-day Keychain-timed lock; a **$29.99/month subscription**; and a separate
   **$19.99 client-side app**.
2. **Loyalty points** — proposed *two incompatible data models*: points on **Pet**
   (with a `LoyaltyHistory` relationship) vs. points on **Client**; and two earning rules
   (per-dollar vs. flat "20/visit → 100").
3. **A SwiftData data-loss scare** — adding `loyaltyPoints` + a `LoyaltyHistory` relationship
   wiped a store; the RTF prescribes `VersionedSchema` + `SchemaMigrationPlan`.
4. **A pile of UI** — animated `LoyaltyPointsBadge`, `CheckoutConfirmationSheet`,
   `LoyaltyRulesControlPanel`.

## Ground truth (what the code actually says)

Every RTF claim was checked against the source. The reconciliation:

| RTF claim / proposal | Reality in the codebase | Consequence |
|---|---|---|
| "You need a `SchemaMigrationPlan`" | **Already exists** — `Core/Storage/Migrations.swift` (`PawtrackrSchemaV1`, `PawtrackrMigrationPlan`), wired into both container builders with `migrationPlan:`. | Alarm is largely stale; see [ADR-0003](0003-swiftdata-migration-discipline.md). |
| "SwiftData silently wipes the file" | This app **fails safe**: `PawtrackrApp.swift:96` try/falls back to local-only; never destructive. | A missing V2 → *throws / appears empty*, not "disk erased." |
| Put `loyaltyPoints` + `LoyaltyHistory` on **Pet** | Loyalty already ships on **Client** — `Client.swift:39 var loyaltyPoints`, `Visit.swift:26 var loyaltyPointsChange`, `LoyaltyEngine`/`LoyaltyService`, accrued in `VisitRepository.applyPoints`. | Pet-based rewrite **rejected**; see [ADR-0002](0002-loyalty-system-evolution.md). |
| Configurable "points per dollar" | Not present — `LoyaltyEngine.calculatePoints` is **hardcoded 1 pt/$1**. No `LoyaltyConfig`, catalog, or history. | Config/catalog/history are *additions*, gated as premium. |
| `@Attribute(.unique) id` on new models | Codebase **forbids** `.unique` under CloudKit (`VisitItem.swift:17` comment). | RTF's loyalty models would be **CloudKit-incompatible**. |
| Product id `com.partnershipwithmedia.pawtrackr.*` | Real bundle id is **`PartnerShipWithMedia.Pawtrackr`**. | Product ids must be namespaced under the real id. |
| Monetization exists | **Greenfield** — zero StoreKit, no paywall, no trial anywhere. | Net-new; `RootView` already orchestrates gates. |
| "Data got wiped for shipped users" | **No evidence it shipped** — v1.0.1, shipped schema is safe additive scalars, no `LoyaltyHistory`, no migration/hotfix commits. Likely a *dev-branch* experience. | Migration ADR is **prevention**, with a recovery contingency. |

## Decisions

Three interlocking ADRs. Monetization is a **business decision the owner made**
(subscription + intro trial); the other two are technical and follow from it.

| ADR | Decision | Status |
|---|---|---|
| [0001](0001-monetization-subscription-trial.md) | Auto-renewable **subscription + 7-day intro free trial** (StoreKit 2), entitlement-gated at `RootView`; the RTF's Keychain-timed non-consumable is rejected (App Review 3.1.1). | Accepted (owner chose) |
| [0002](0002-loyalty-system-evolution.md) | Keep loyalty on **Client**; add `LoyaltyConfig` (+ optional `LoyaltyHistory`, rewards catalog) **additively**, as premium features. Reject the Pet-based rewrite and `@Attribute(.unique)`. | Proposed |
| [0003](0003-swiftdata-migration-discipline.md) | Any new `@Model`/relationship/rename/type-change requires a **V2 `VersionedSchema` + `MigrationStage` + CloudKit production schema deploy**. Monetization needs no new model; loyalty additions land as V2. | Proposed |

## The through-line

The three RTF contradictions all resolve the same way: **ground in the shipped code, add
additively, and let Apple's own mechanisms do the work you were about to hand-roll.** The
subscription intro offer replaces the Keychain trial timer; the existing Client-based loyalty
replaces the Pet rewrite; the existing migration plan (advanced to V2) replaces the panic.
