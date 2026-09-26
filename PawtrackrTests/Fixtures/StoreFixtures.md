# Store fixtures

Real SwiftData stores captured from shipped builds. `StoreUpgradeRegressionTests`
opens each one with the current model list, which is exactly what happens on a
user's device after an App Store update.

| File | Captured from | Contents |
|------|---------------|----------|
| `Pawtrackr-1.0.1-build2.sqlite` | 1.0.1 (2), commit `8c8f39d`, iOS 26.5 simulator, CloudKit mirroring on | 3 clients (Ava Martinez, Jordan Lee, Rosa Upgradetest), 2 pets, 4 visits, 1 business config. 19 entities, no loyalty tables. |
| `Pawtrackr-1.0.2-build3.sqlite` | 1.0.2 (3), commit `16c623a`, same simulator, written after the recovery-screen reset through 1.0.2's staged plan | 3 clients (Ava Martinez, Jordan Lee, Nina Afterreset), 2 pets, 4 visits, 1 loyalty config, 4 reward templates. 22 entities. |

How the 1.0.1 fixture was made: install the 1.0.1 build on a fresh simulator,
finish onboarding with the sample salon, add one client by hand, terminate the
app, then copy `Library/Application Support/Pawtrackr.store*` out of the data
container and run `PRAGMA wal_checkpoint(TRUNCATE); VACUUM;` on the copy so it
is a single self-contained file.

When a release ships, capture its store the same way and add a row here.
Never regenerate an existing fixture from a newer build — the point is to keep
the exact bytes an older build wrote.
