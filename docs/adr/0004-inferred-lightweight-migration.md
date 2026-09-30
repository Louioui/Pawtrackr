# ADR-0004: Open the store with inferred lightweight migration, not a staged plan

**Status:** Accepted — supersedes the staged-plan parts of [ADR-0003](0003-swiftdata-migration-discipline.md)
**Date:** 2026-09-25
**Deciders:** Luis (solo developer)

## Context — the 1.0.2 incident

A customer updated from 1.0.1 to 1.0.2 through the App Store (no reinstall) and every client
disappeared. Reproduced on a clean iOS 26.5 simulator by installing a 1.0.1 build (`8c8f39d`),
adding clients, then installing the 1.0.2 build (`16c623a`) over it:

1. 1.0.1 wrote a store with 19 entities. Its plan was `schemas: [V1]`, `stages: []`, so SwiftData
   did plain inferred migration and never compared the store against a versioned schema.
2. 1.0.2 edited the already-shipped `PawtrackrSchemaV1` in place (added `LoyaltyLedgerEntry`,
   1.0.6 → 1.0.7), added `PawtrackrSchemaV2` (+ `LoyaltyConfig`, `LoyaltyRewardTemplate`), and
   the first non-empty `.lightweight` stage. Both versions listed the **live** model classes.
3. A non-empty stage list switches Core Data to staged migration, which only opens a store whose
   model checksum matches one of the plan's schemas. The 1.0.1 store (19 entities) matched neither
   V1 (20) nor V2 (22): `NSCocoaErrorDomain 134504 "Cannot use staged migration with an unknown
   model version."` The local-only fallback used the same plan and threw the same error.
4. With no container, the app showed `DataStoreRecoveryView`: *"Your iCloud data is safe and will
   re-download once we reset the local copy"* above a prominent **Reset Local Data** button. The
   reset moved the store into `Application Support/RecoveryBackup-<stamp>/` and the app relaunched
   empty. Nothing came back from iCloud, so the clients looked erased. They were never deleted.

ADR-0003 already said "never edit a shipped version in place" and "copy the prior version's
models". Both were broken by one convenient edit, and nothing tested an old store.

## Decision

1. **No `SchemaMigrationPlan`.** Every container (app primary + local-only fallback, App Intents,
   `DataStoreService`) is built with `ModelContainer(for: schema, configurations:)`. SwiftData then
   infers a lightweight migration from the model Core Data caches inside each store (`Z_MODELCACHE`),
   so any shipped build's store can be opened. `PawtrackrSchema` is a plain model list.
2. **Changes stay additive** — the only kind CloudKit accepts anyway: new models, new optional or
   defaulted properties, new optional relationships, renames via `@Attribute(originalName:)`.
   No unique constraints (`@Attribute(.unique)`, `#Unique`): CloudKit can't enforce them and the
   mirrored container fails to load. Data fix-ups run at launch in `DataMigrations` (already the
   pattern here), not in migration stages. Every model change then follows the release checklist in
   [`docs/icloud-validation.md`](../icloud-validation.md): add the model's `CD_<Model>` line to
   `docs/cloudkit/required-record-types.txt`, push the schema to Development with the DEBUG
   `CloudKitSchemaInitializer` (`-PawtrackrInitCloudKitSchema`), and deploy it to Production before
   archiving.
3. **Upgrades are tested against real shipped stores.** `PawtrackrTests/Fixtures/` holds a store
   captured from each release; `StoreUpgradeRegressionTests` opens it with today's models. Add a
   fixture every time a build ships (procedure in `Fixtures/StoreFixtures.md`).
4. **CI enforces it.** `ci_scripts/ci_pre_xcodebuild.sh` fails the build if a staged plan
   reappears in the app target, the upgrade test/fixtures go missing, a model in
   `PawtrackrSchema.models` declares a unique constraint, or `docs/cloudkit/required-record-types.txt`
   drifts from `PawtrackrSchema.models`. On an archive with a `CKTOOL_MANAGEMENT_TOKEN` secret, it
   also fails when the CloudKit Production schema lacks one of those record types, or a field that
   Development has for them.
5. **Failure is never steered into data loss.** The recovery screen says the data is still on the
   device, shows the client count, makes "Send Details to Support" the primary action, and hides
   Reset under Advanced behind a confirmation. `StoreBackupRestore` lets users bring back any
   `RecoveryBackup-*` / `PreMigrationBackup-*` store from Settings › Data or a banner.

## Options considered

| Option | Opens 1.0.1 stores | Opens 1.0.2 stores | Next model change | Cost |
|---|---|---|---|---|
| **A. No plan, inferred migration (chosen)** | Yes — verified on simulator + fixture test | Yes — verified | Additive changes just work | Delete code |
| B. Revert V1 to the exact 19 live classes | Yes (checksums match today) | Yes | Any stored-property edit silently changes V1's and V2's checksums again → 134504 for everyone | Small, fragile |
| C. Frozen nested `@Model` copies per version | Yes, if copied exactly | Yes | Correct, but every release copies ~20 models | Large; one typo = 134504 |

B keeps the trap that caused the incident. C is Apple's textbook answer, but it buys nothing a
CloudKit-mirrored store can use: CloudKit only accepts additive changes, which inferred migration
already handles. If a non-lightweight change is ever truly needed, reintroduce a plan with frozen
copies (option C) **and** add a fixture for every shipped build before the release.

## Consequences

- An in-place update from any shipped build opens the existing store; there's no version ladder to maintain.
- The inference relies on Core Data's cached model (`Z_MODELCACHE`), which isn't documented as a
  contract. The fixture tests are what make that safe to depend on; keep adding fixtures.
- New record types and fields still need **Deploy Schema Changes to Production** in the CloudKit
  Console before release (unchanged from ADR-0003). The archive gate checks it with the
  management token; without the token the archive fails unless
  `PAWTRACKR_SKIP_CLOUDKIT_PRODUCTION_CHECK=1` says Production was checked by hand
  (`docs/icloud-validation.md`).
- Users who already reset on 1.0.2 keep their data in `RecoveryBackup-*`; 1.0.3 offers it back.
