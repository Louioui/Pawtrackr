# ADR-0005: Keep Pawtrackr persistence on this device

**Status:** Accepted; supersedes the remote persistence and schema deployment parts of earlier ADRs.
**Date:** 2026-09-29

Pawtrackr opens its existing `Pawtrackr` named SwiftData store through
`LocalStoreConfiguration`, with `cloudKitDatabase: .none`. App Intents use the
same bootstrap container. Settings remain in local UserDefaults; the app has
no account checks, remote uploads, presence heartbeats, or remote push hooks.

The change preserves every shipped model type and stored property, including
legacy device metadata. It keeps the same store URL and device identity key.
Inferred lightweight migration, additive model changes, and shipped-store
fixture tests remain required under ADR-0004. Removing remote persistence
does not reset the database or delete the data previously downloaded to it.

Scheduled restores, per-build backups, and legacy store moves still finish
before the container opens. Recovery archives and their photos remain
available through Restore Clients. Local exports and backups provide the
user's recovery options; the app makes no promise of automatic cloud recovery.

CI rejects implicit SwiftData configurations, remote persistence APIs, cloud
entitlements, and remote push capabilities. Normal builds and archives run the
same local checks without management tokens or remote schema access. Earlier
incident and deployment documents remain historical records.
