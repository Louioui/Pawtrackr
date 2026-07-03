# ADR-0003: SwiftData migration discipline for structural changes (V2 + stage + CloudKit deploy)

**Status:** Proposed
**Date:** 2026-07-03
**Deciders:** Luis (solo developer)

## Context

The RTF's most urgent thread is a **data wipe** after adding `loyaltyPoints` + a `LoyaltyHistory`
relationship. Reconciled against the code:

- Migration infrastructure **already exists** — `Core/Storage/Migrations.swift` defines
  `PawtrackrSchemaV1` (`versionIdentifier 1.0.6`, all 19 models) and `PawtrackrMigrationPlan`,
  wired into both container builders (`DataStoreService.swift:37`, `PawtrackrApp.swift:96/110`,
  `AppIntents.swift:164`) via `migrationPlan:`.
- The plan is **frozen at V1**: `schemas: [PawtrackrSchemaV1.self]`, `stages: []`.
- The documented convention is: *"property addition with a default → still V1 compatible
  (lightweight), bump the patch."* That is why `Client.loyaltyPoints: Int = 0` was safe — an
  additive scalar SwiftData auto-migrates.
- The app **fails safe**, not destructive: `PawtrackrApp.swift` catches a failed
  `ModelContainer` init and falls back to **local-only** (`cloudKitDatabase: .none`); it never
  does a destructive recreate. (`DataStoreService`'s convenience init instead
  `preconditionFailure`s — a hard crash, not a wipe.)
- CloudKit is `.automatic` (private DB) when `AppRuntime.allowsICloudSync`.
- **No evidence a wipe shipped**: marketing version 1.0.1; the shipped schema is safe additive
  scalars; there is no `LoyaltyHistory` in the tree and no migration/wipe/hotfix commit. The
  RTF's episode was almost certainly a dev-branch experience with the (rejected) Pet-based code.

The gap: the "additive scalar → stay on V1" convention is safe for scalars but is **not a safe
assumption for new relationships, renames, or type changes** — nor for the **CloudKit production
schema deploy** any new type requires. A new *standalone* model is often auto-migrated as
lightweight; what reliably bites is (a) new/changed **relationships** (the RTF's
`Pet ↔ LoyaltyHistory` is the exact case that broke), and (b) forgetting to **deploy the schema to
CloudKit Production** — after which a synced store can't reconcile the new type and users see an
*empty* app, which is how the "wipe" reads. [ADR-0002](0002-loyalty-system-evolution.md)
(`LoyaltyConfig`/`LoyaltyHistory`/`LoyaltyReward`) is squarely in this territory.

## Decision

Codify a **structural-change protocol**. A change is *structural* if it adds/removes a `@Model`
type, adds/removes/renames a **relationship**, renames a property, or changes a property's type.
Additive **scalar** properties *with defaults* remain lightweight (bump the patch, stay V1).

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
6. Run the **upgrade test** (already in the RTF checklist and `CLAUDE.md`): install the *old*
   build, create records, then run the *new* build **without deleting** — data must survive.

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

1. [ ] When loyalty models land (ADR-0002): create `PawtrackrSchemaV2` (V1 models + `LoyaltyConfig`
       [+ `LoyaltyHistory`, `LoyaltyReward`]), add a `.lightweight` stage V1→V2, re-point the typealias.
2. [ ] Confirm new models use plain `UUID` ids (no `.unique`) and optional/defaulted relationships.
3. [ ] Add "Deploy CloudKit schema to Production" to the release checklist
       (`docs/XcodeCloudDeployment.md` already lists "migration plan presence" — extend it).
4. [ ] Add the old-build → new-build upgrade test to CI or the pre-release ritual.
5. [ ] Keep monetization schema-free: entitlement stays in StoreKit + a `UserDefaults`/Keychain cache.
