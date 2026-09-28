# ADR-0003: SwiftData migration discipline for structural changes

**Status:** Accepted
**Date:** 2026-07-03
**Deciders:** Luis (solo developer)

## Context

The RTF's most urgent thread was a **data wipe** after adding `loyaltyPoints` + a
`LoyaltyHistory` relationship. The original 1.0.1 reconciliation showed:

- Migration infrastructure existed — `Core/Storage/Migrations.swift` defined
  `PawtrackrSchemaV1` (`versionIdentifier 1.0.6`, all 19 models) and `PawtrackrMigrationPlan`,
  wired into the app container builders via `migrationPlan:`.
- The 1.0.1 plan was **frozen at V1**: `schemas: [PawtrackrSchemaV1.self]`, `stages: []`.
- The documented convention is: *"property addition with a default → still V1 compatible
  (lightweight), bump the patch."* That is why `Client.loyaltyPoints: Int = 0` was safe — an
  additive scalar SwiftData auto-migrates.
- The app **fails safe**, not destructive: `PawtrackrApp.swift` catches a failed
  `ModelContainer` init and falls back to **local-only** (`cloudKitDatabase: .none`); it never
  does a destructive recreate. (`DataStoreService`'s convenience init instead
  `preconditionFailure`s — a hard crash, not a wipe.)
- CloudKit is `.automatic` (private DB) when `AppRuntime.allowsICloudSync`.
- A 1.0.2-era regression later violated this ADR: the shipped V1 was edited in place from
  `1.0.6`/19 models to `1.0.7`/20 models by adding `LoyaltyLedgerEntry`, then the current schema
  added `LoyaltyConfig` and `LoyaltyRewardTemplate`. A real 1.0.1 store no longer matched any
  schema in the migration chain, so SwiftData could refuse to open it or the app could appear
  empty after update even though the SQLite file still existed.

The gap: the "additive scalar → stay on V1" convention is safe for scalars but is **not safe for
new `@Model` types, new relationships, renames, or type changes**. Any new type also requires a
CloudKit production schema deploy before App Store release. The 1.0.2 regression proved the
procedural rule matters: never edit a shipped schema in place.

## Decision

Codify a **structural-change protocol**. A change is *structural* if it adds/removes a `@Model`
type, adds/removes/renames a **relationship**, renames a property, or changes a property's type.
Additive **scalar** properties *with defaults* can remain in the current schema version only until
that version ships. Once shipped, freeze it forever.

Any **structural** change requires, before shipping:

1. A new frozen `PawtrackrSchemaVN: VersionedSchema` (copy the prior version's models, apply the
   change). **Never edit a shipped version in place.**
2. Append it to `PawtrackrMigrationPlan.schemas` (never remove/reorder prior versions).
3. Add a `MigrationStage` for the transition — `.lightweight` for purely additive
   (new optional-or-defaulted models/relationships), `.custom` (`willMigrate`/`didMigrate`) for
   renames, type changes, or backfills.
4. Re-point `typealias PawtrackrSchema = PawtrackrSchemaVN`.
5. **CloudKit:** new relationships must be **optional or defaulted**; **no `@Attribute(.unique)`**
   (the codebase already forbids it — `VisitItem.swift:17`); then **Deploy Schema Changes to
   Production** in the CloudKit Console before the App Store release.
6. Run the **upgrade test**: create/open an old store with real records, then run the new build
   **without deleting the app** — data must survive.

Current chain:

- `PawtrackrSchemaV1` = `1.0.6`, 19 models, shipped in 1.0.1.
- `PawtrackrSchemaV2` = `1.0.7`, adds `LoyaltyLedgerEntry`.
- `PawtrackrSchemaV3` = `1.1.0`, adds `LoyaltyConfig` and `LoyaltyRewardTemplate`.

## Options Considered

### Option A: Keep "stay on V1, bump the patch" for everything
**Pros:** no ceremony. **Cons:** works only for scalars; the moment loyalty adds a **relationship**
(or the CloudKit prod schema isn't deployed), a synced store can't reconcile and users see an
empty app. **Rejected** — this is the exact failure the RTF hit.

### Option B: Versioned schema + explicit stage for every structural change (chosen)
| Dimension | Assessment |
|-----------|------------|
| Safety | Users' stores climb V1→V2→… deterministically; no throw-on-launch. |
| CloudKit | Forces the prod-schema-deploy step into the checklist. |
| Cost | A few minutes per structural change + one upgrade test. |

**Pros:** deterministic, CloudKit-safe, catches the empty-app failure before users do.
**Cons:** discipline overhead (mitigated — it's a checklist, and the infra already exists).

## Trade-off Analysis

The infrastructure is already correct; the risk is purely *procedural* — knowing **when** a change
crosses from "lightweight scalar" into "needs a version." The bright line is **new models and
relationships**, which is precisely the loyalty work. Encoding that line as a checklist (plus the
CloudKit production deploy, the step most likely to be forgotten because it lives outside Xcode)
converts a latent production incident into a routine step.

Monetization ([ADR-0001](0001-monetization-subscription-trial.md)) deliberately introduces **no new
`@Model`** (entitlement lives in StoreKit + a `UserDefaults`/Keychain cache), so it needs none of
this — a point worth protecting: *don't* persist a subscription entity and drag the schema along
for no reason.

## Consequences

- **Easier:** loyalty (and any future feature) ships without the empty-app failure; the CloudKit
  prod deploy stops being the forgotten step.
- **Harder:** each structural change is a few extra minutes (new version enum + stage + one test).
- **Recovery contingency (if a bad build ever reaches users):** SwiftData does not erase the
  on-disk SQLite; it refused to open it. Shipping a build with the correct `VersionedSchema` +
  stage (and the CloudKit prod schema deployed) lets the app re-read the existing store — records
  reappear. Keep this in mind if a TestFlight/App Store build ever shows empty accounts.

## Action Items

1. [x] Restore shipped V1 as `1.0.6` with 19 models.
2. [x] Split loyalty additions into additive V2/V3 stages.
3. [x] Add a unit regression that opens a V1 store with clients through the current migration plan.
4. [ ] Deploy CloudKit schema changes to Production before App Store release.
5. [ ] Run the real-device old-build -> new-build upgrade test before submitting.
6. [ ] Keep monetization schema-free: entitlement stays in StoreKit + a `UserDefaults`/Keychain cache.
