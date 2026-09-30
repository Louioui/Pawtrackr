# iCloud Validation Checklist

Run this checklist before shipping any build that changes SwiftData models,
CloudKit sync behavior, or iCloud entitlements. The release checklist applies to
every App Store and TestFlight build.

## Release Checklist

Do these in order. Steps 2 and 3 are only needed when a model changed since the last release.

1. **Keep the model change additive** (ADR-0004): new models, optional or
   defaulted properties, optional relationships, `@Attribute(originalName:)`
   renames. No unique constraints. If you added a model to `PawtrackrSchema.models`,
   add its `CD_<Model>` line to `docs/cloudkit/required-record-types.txt`.
   CI fails the build if the two lists differ or a schema model declares
   `@Attribute(.unique)` or `#Unique`.
2. **Push the schema to Development** with the DEBUG initializer
   ([below](#push-the-schema-to-development)).
3. **Deploy it to Production** in CloudKit Console
   ([below](#deploy-the-schema-to-production)). TestFlight and App Store builds
   talk to Production. If Production lacks a record type or field, every upload
   batch that carries it is rejected while imports keep working, so the app looks
   healthy.
4. **Archive.** With `CKTOOL_MANAGEMENT_TOKEN` set, `ci_pre_xcodebuild.sh`
   fails the archive if Production lacks anything
   ([token setup](#cloudkit-management-token)). Without the token the archive
   fails too. If you can't add the token yet, check Production by hand and set
   `PAWTRACKR_SKIP_CLOUDKIT_PRODUCTION_CHECK=1` on the workflow; the archive then
   passes with a warning. Remove the variable once the token is in place.
5. **Run the install-over upgrade test** ([Existing Data Migration](#existing-data-migration)).
   Install the previous App Store build, add data, then install the new build
   over it without deleting the app.
6. **Add the release's store fixture** to `PawtrackrTests/Fixtures` once the
   build ships (procedure in `PawtrackrTests/Fixtures/StoreFixtures.md`).
7. **Run the device matrix** ([Device Matrix](#device-matrix)) whenever sync,
   account handling, or entitlements changed.
8. **Watch the failure reports** in the days after release
   ([iCloud Failure Reports](#icloud-failure-reports)). A `schemaRejected`
   report means step 3 missed something.

## CloudKit Schema

### Push the schema to Development

Development normally only contains the record types and fields that a debug build
happened to upload with a non-nil value. Development is what gets deployed, so
anything missing there is missing in Production too. `CloudKitSchemaInitializer`
(DEBUG builds only) uploads a representative record for every model with every
field set, then deletes it. It uses a throwaway store in the temporary directory,
never `Pawtrackr.store`.

Requirements: a Debug build, on a simulator or device signed in to iCloud.

**From Xcode:** Product › Scheme › Edit Scheme… › Run › Arguments › Arguments
Passed On Launch: add `-PawtrackrInitCloudKitSchema`, run once, then untick it.
Don't commit the scheme with it ticked, or every debug launch pays for a
CloudKit round trip.

**From the command line:** `xcodebuild` can't pass launch arguments to the app,
so build, install, and launch it separately:

```sh
xcrun simctl list devices available            # pick a booted, iCloud-signed-in simulator
UDID=<simulator UUID>
xcodebuild -project Pawtrackr.xcodeproj -scheme Pawtrackr -configuration Debug \
  -destination "id=$UDID" -derivedDataPath build/SchemaInit build
xcrun simctl install "$UDID" build/SchemaInit/Build/Products/Debug-iphonesimulator/Pawtrackr.app
xcrun simctl spawn "$UDID" log stream --level info \
  --predicate 'subsystem == "PartnerShipWithMedia.Pawtrackr" AND category == "CloudKitSchema"' &
xcrun simctl launch "$UDID" PartnerShipWithMedia.Pawtrackr -PawtrackrInitCloudKitSchema
```

Success logs `CloudKit Development schema initialized for 22 models`. A failure
logs the full error. A model CloudKit can't accept fails here with a validation
error. That's the cheapest place to find out.

The throwaway store also imports the Development zone while it's open, so the
run is slower when the dev account has a lot of data. That's expected.

### Deploy the schema to Production

1. Open CloudKit Console → CloudKit Database → `iCloud.PartnerShipWithMedia.Pawtrackr`
   → Development → Schema → Record Types. Check that every type in
   `docs/cloudkit/required-record-types.txt` is there.
2. Choose **Deploy Schema Changes…**, review the list, and deploy. Deployment is
   permanent: Production can never drop a type or field. Only deploy what this
   release's models actually use.
3. Switch to Production → Record Types and confirm every `CD_` type is there,
   with every field.

To check Production from the command line with a saved management token:

```sh
xcrun cktool export-schema --team-id 6ALS97634D \
  --container-id iCloud.PartnerShipWithMedia.Pawtrackr \
  --environment production --output-file /tmp/pawtrackr-production.ckdb
```

To run the same gate as the archive locally, without the token landing in shell history:

```sh
read -rs CKTOOL_MANAGEMENT_TOKEN && export CKTOOL_MANAGEMENT_TOKEN
CI_XCODEBUILD_ACTION=archive sh ci_scripts/ci_pre_xcodebuild.sh
```

The gate compares Production with a live Development export for the types in
`required-record-types.txt`. If Development still has a field from an abandoned
experiment, the clean fix is **Reset Development Environment** in CloudKit Console,
then rerun the initializer. Otherwise add `ignore CD_<Type>.CD_<field>` to the
list with a comment explaining why.

### CloudKit management token

The gate needs a CloudKit management token. A management token can read both
schemas and can change or reset the Development schema. It can't deploy to
Production. Treat it as a secret.

1. In CloudKit Console, open your user account's Settings and generate a
   management token. Copy it right away, because the Console won't show it again.
2. For local use, store it in the login keychain: `xcrun cktool save-token --type management`.
3. For Xcode Cloud, add it to every workflow that archives: workflow → Environment →
   Environment Variables → name `CKTOOL_MANAGEMENT_TOKEN`, value the token,
   **Secret** ticked. The script passes it to `cktool` through the environment,
   never on the command line.

Management tokens expire. When an archive fails with "couldn't export the
CloudKit production schema", replace the token first.

## iCloud Failure Reports

When iCloud permanently refuses a device's sync (`schemaRejected`,
`limitExceeded`, or `setupFailedWhileSignedIn`), the app saves one
`PTSyncFailureReport` record to the container's public database. Each kind is
sent at most once a day per device. A report holds only the disposition, error
domain and code, app version and build, OS version and platform: no client
data. CloudKit still attaches its own creator ID (see below). Nothing is
sent from tests, local-only launches, or DEBUG builds without
`-PawtrackrSendSyncFailureReports`.

`docs/cloudkit/sync-failure-reports.md` has everything else:

- **One-time setup:** create the type in Development by running a DEBUG build
  once with `-PawtrackrSendSyncFailureReports`. Add the indexes. Set the security
  roles to `_world` none, `_icloud` Create, `_creator` Create and Write. Then
  deploy to Production. Until the type is in Production, reports fail quietly
  (logged, nothing else affected). The archive gate doesn't check this type.
- **Reading reports:** Console › Production › Records › Public Database ›
  `PTSyncFailureReport`.
- **App Privacy:** add Diagnostics › Other Diagnostic Data, purpose App
  Functionality, not used for tracking. Whether it's linked depends on how you
  treat CloudKit's `creatorUserRecordID`; the page lays out both answers.

## Devices and Accounts

- Use two physical devices signed into the same iCloud account.
- Use one fresh iCloud account with no Pawtrackr records.
- Use one existing account with real migrated Pawtrackr data.
- Test with the development CloudKit environment first, then production.

## Fresh Install

- Delete Pawtrackr from both devices.
- Install the new build on device A.
- Create a business profile, client, pet, visit, appointment, payment, and photos.
- Install the same build on device B.
- Confirm records restore without duplicate clients, pets, visits, services, or summary rows.
- Confirm the first-sync gate appears only once and can be skipped without returning on next launch.

## Existing Data Migration

- Install the previous shipping build.
- Create at least 10 clients, 20 pets, completed visits, active visits, appointments, payments, custom services, message templates, and photos.
- Upgrade to the new build without deleting the app.
- Confirm the app opens without the data recovery screen.
- Confirm active visits, client detail, pet detail, checkout, settings, and insights all load.
- Confirm custom services were not deleted or overwritten.

## Multi-Device Sync

- On device A, create a client and pet.
- Confirm device B receives them after foregrounding and after a silent push.
- On device B, add a visit and payment.
- Confirm device A receives the visit and payment.
- Edit the same client on both devices while offline, reconnect, and confirm the app remains usable after CloudKit conflict resolution.
- Delete a client with pets and visits on one device, then confirm the delete cascades on the other.

## Offline and Account States

- Turn on Airplane Mode, create a client, pet, visit, and payment, then reconnect.
- Sign out of iCloud and confirm the banner/status copy is clear and the app does not freeze.
- Sign back into iCloud and confirm sync resumes.
- Fill or simulate iCloud quota issues where possible and confirm quota messaging appears.

## Device Matrix

Run each case on iOS and on macOS.

- **iCloud Drive off, CloudKit on.** Sync should keep working. Note whether a
  "Check iCloud access" warning appears. The `ubiquityIdentityToken` check is
  known to raise it falsely in this state.
- **Pawtrackr's per-app iCloud switch off.** Record what the banner and
  Settings say, and confirm nothing claims the clients are backed up.
- **Sign out of iCloud and back in, and switch Apple IDs.** Confirm what the
  system purges locally, and that the copy on screen matches it.
- **Siri or Shortcuts intent while the app is open.** Watch Console.app for
  error 134422.
- **Two idle devices left open for 10 minutes.** Log how many rows each summary
  rebuild writes. Steady writes on idle devices mean upload churn.
- **Schema rejection shape (once, not every release).** Use a TestFlight build of
  a throwaway branch that adds an undeployed optional field, signed in with a
  test Apple ID, and capture the CKError tree so the error-classifier tests use a
  real shape. Never deploy that field. The same run should put one
  `schemaRejected` report in Production's public database. That's the only
  end-to-end check of the failure reports.
- **Signed-in store fixture (once).** Capture a store from a device that is signed
  in to iCloud and has completed exports, and add it next to the simulator
  fixtures. The current fixtures have no iCloud account.

## CloudKit Dashboard

- Inspect record types for all SwiftData models (the list is `docs/cloudkit/required-record-types.txt`).
- Confirm the development schema reflects the current build (run the initializer first).
- CI blocks unique constraints on schema models. Still confirm every relationship is optional and every attribute is optional or has a default.
- Confirm private database indexes support common fields used by CloudKit/SwiftData.
- Run the device matrix against Development builds first. Deploy to Production
  before you archive: TestFlight builds need Production, and the archive gate
  fails without it.
- Confirm Production has `PTSyncFailureReport` with `_world` unable to read it,
  and check its records for new reports
  ([iCloud Failure Reports](#icloud-failure-reports)).

## Performance

- Test with at least 2,000 clients, 3,000 pets, 10,000 visits, and photos on older hardware.
- Open Dashboard, Clients, Client Detail, Pet Detail, Checkout, Recent History, Insights, Settings, and iCloud Diagnostics.
- Confirm scrolling remains responsive and app launch does not block on summary rebuilds.
- Confirm memory use stays stable while opening photo-heavy records.
