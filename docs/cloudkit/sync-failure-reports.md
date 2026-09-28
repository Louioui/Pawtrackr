# iCloud Failure Reports (Public Database)

When iCloud permanently refuses Pawtrackr's sync on a device, the app saves one
`PTSyncFailureReport` record to the **public** database of
`iCloud.PartnerShipWithMedia.Pawtrackr`. That's how you hear about a broken
Production schema within hours, instead of from a groomer who lost clients.
Pawtrackr has no server, and this is the only report you can read.

Code: `Pawtrackr/Core/Storage/Sync/CloudKitPublicSyncFailureReporter.swift`.
`CloudKitMonitor` hands every classified failure to it and to the local-log
reporter (`TelemetrySyncFailureReporter`).

## What gets sent, and when

A report goes out for three dispositions only:

| Disposition | Meaning |
| --- | --- |
| `schemaRejected` | Production lacks a record type or field this build uploads. Every upload batch that carries it is rejected. |
| `limitExceeded` | A record is over CloudKit's size limits. |
| `setupFailedWhileSignedIn` | Mirroring setup failed (134400) while the account is signed in. Usually the per-app iCloud switch is off; then the report's own save fails too, so the ones that arrive point at the container or entitlements. |

Each disposition is reported at most once every 24 hours per device. The
last-sent dates live in UserDefaults (`cloudkit.failureReport.publicLastSent.*`),
separate from the local-log reporter's. A failed save still uses up the day's
allowance, so a device that can't save isn't retrying on every export.

The save runs off the main actor, fire and forget. Nothing is ever sent:

- from unit tests or UI tests, even with the launch argument;
- when the store isn't mirroring (local-only fallback, or iCloud off for the launch);
- from DEBUG builds, unless the launch argument `-PawtrackrSendSyncFailureReports` is present.

A public save needs a signed-in account, a network and the record type deployed
to Production. When one is missing, the save fails, and the app logs
`Couldn't send iCloud failure report <disposition>: <domain> <code>` (category
`CloudKit`) and carries on. The groomer never sees it, and her data isn't touched.

## The record

| Field | CloudKit type | Example |
| --- | --- | --- |
| `disposition` | STRING | `schemaRejected` |
| `errorDomain` | STRING | `CKErrorDomain` |
| `errorCode` | INT(64) | `12` |
| `appVersion` | STRING | `1.0.3` |
| `buildNumber` | STRING | `4` |
| `osVersion` | STRING | `26.5.0` |
| `platform` | STRING | `iOS`, `iPadOS` or `macOS` |

That's the whole record. It has no client, pet or visit data, no names, no
device name, no CloudKit server message (it can name record types and IDs) and
no identifier the app makes up. `CloudKitPublicSyncFailureReporterTests` fails
if a field is added. If you ever add one, update this page and the App Privacy
answers too.

CloudKit adds its own system fields to every record, and the app can't stop it:
the created and modified timestamps, and the user record IDs of the creator and
last modifier (`createdUserRecordName` / `modifiedUserRecordName` in the Console).
See [App Privacy](#app-privacy-app-store-connect) for what the creator ID means.

## One-time setup in CloudKit Console

Public record types exist only once a record of that type has been saved, and
Development creates missing types on demand. Real reports never fire in
Development, so the DEBUG build saves a sample instead.

1. **Create the type in Development.** Launch a Debug build that is signed in to
   iCloud once, with `-PawtrackrSendSyncFailureReports`:
   - Xcode: Edit Scheme… › Run › Arguments › Arguments Passed On Launch. Untick
     it afterwards. Each launch with it saves another sample, and a DEBUG build
     that has it also sends real reports to Development.
   - Command line: build and install as in
     [Push the schema to Development](../icloud-validation.md#push-the-schema-to-development),
     then run `xcrun simctl launch "$UDID" PartnerShipWithMedia.Pawtrackr -PawtrackrSendSyncFailureReports`.

   The launch saves one record with `disposition` = `developmentSample` and every
   field set. Success logs `Sent iCloud failure report developmentSample`
   (subsystem `PartnerShipWithMedia.Pawtrackr`, category `CloudKit`).
2. **Check the fields.** Development › Schema › Record Types › `PTSyncFailureReport`:
   six STRING fields and `errorCode` as INT(64).
3. **Add indexes.** Schema › Indexes › `PTSyncFailureReport`:
   - `recordName` QUERYABLE. The Console can't list the records without it.
   - `createdTimestamp` SORTABLE, to see the newest first.
   - `disposition` QUERYABLE (optional), to filter by kind.
4. **Set the security roles.** Schema › Security Roles, row `PTSyncFailureReport`.
   A new public type lets everyone read it by default. Change it to:
   - `_world`: nothing. Untick **Read**, or anyone could read every report.
   - `_icloud`: **Create** only.
   - `_creator`: **Create** and **Write**. No Read: the app never reads reports back.
5. **Check it in Development.** Launch the Debug build with the argument once more:
   - A second `developmentSample` record must appear. If the log shows a
     permission failure (`CKErrorDomain 10`) instead, give `_creator` **Read**
     as well. That only lets an account read the reports it created itself.
   - Records › Public Database › `_defaultZone` › `PTSyncFailureReport` ›
     Query Records must still list both samples with `_world` Read removed.
     If it doesn't, fix that before deploying. Don't give `_world` Read back.
6. **Deploy.** Development › **Deploy Schema Changes…**. This carries the type,
   its fields, indexes and security roles to Production. Records don't deploy,
   so the samples stay in Development. Deployment is permanent: Production can
   never drop the type or a field. Check that the dialog lists nothing you
   didn't mean to ship.
7. **Confirm Production.** Production › Schema › Record Types, Indexes and
   Security Roles should match steps 2 to 4.

Until step 6 is done, TestFlight and App Store saves fail because the type is
missing, and are logged. Nothing else is affected.

This is a public-database type, not a SwiftData model. The mirrored `CD_` types
in the private database don't change, so ADR-0004 and the "no schema change in
a hotfix" rule aren't touched. `ci_pre_xcodebuild.sh` doesn't check this type
in Production. `required-record-types.txt` only takes `CD_` lines. Check it by
hand (step 7).

## Reading reports

CloudKit Console › CloudKit Database › `iCloud.PartnerShipWithMedia.Pawtrackr` ›
**Production** › Records. Set Database to **Public Database**, Zone to
`_defaultZone` and Record Type to `PTSyncFailureReport`, then **Query Records**.
Sort by `createdTimestamp`.

- **`schemaRejected`**: Production is missing something the reported build
  uploads. Deploy the Development schema ([Deploy the schema to Production](../icloud-validation.md#deploy-the-schema-to-production)).
  Until you do, every upload on that build is refused while downloads keep working.
- **`limitExceeded`**: a record is too large. Look at what that build writes
  (photos, notes, JSON blobs).
- **`setupFailedWhileSignedIn`**: one now and then is a groomer with the
  per-app switch off. Several from one build point at the container,
  entitlements or provisioning profile.

A report tells you something is wrong, not whose data. The groomer's Copy
Diagnostics or support report has the full failure log, with CloudKit's own message.

CloudKit never deletes public records. Delete old reports in the Console now
and then, and match whatever retention your privacy policy promises.

## App Privacy (App Store Connect)

This changes the App Privacy answers. If the label currently says **Data Not
Collected**, it won't any more.

- **Data type:** Diagnostics › **Other Diagnostic Data**. The reports are error
  classifications, not Crash Data or Performance Data.
- **Purpose:** App Functionality.
- **Used for tracking:** No.
- **Linked to the user:** your call. Here are the facts.

**What `creatorUserRecordID` is.** Pawtrackr doesn't add an identifier, but
CloudKit stamps every saved record with the creator's user record ID, and you
can see it on each report in the Console.

- It's scoped to this container. The same Apple ID has a different ID in every
  other developer's container, so it can't be matched across apps.
- It's stable within this container: the same on all of the groomer's devices
  and across reinstalls. Reports from one groomer can be grouped, and her
  iPhone and Mac look like one user.
- It doesn't give you a name or email. Turning it into a person needs user
  discoverability, which Pawtrackr never requests and Apple deprecated in iOS 17.
- It doesn't lead to her clients. You can't read groomers' private databases,
  and Pawtrackr has no other server or account system that stores the ID.

**The two answers.**

- **Linked to you** is the conservative answer. Apple counts data as linked when
  it's tied to an account or user-level ID, and every report carries one. If you
  choose it, also decide whether to declare Identifiers › **User ID**, since you
  can see the ID and keep it as long as the record exists.
- **Not linked to you** is defensible if you treat the ID as an app-scoped
  pseudonym you can't tie to anyone, and you never join it with anything else
  (support email, a future backend, analytics). If Pawtrackr ever stores user
  record IDs anywhere, revisit this answer.

Mention the reports in the privacy policy either way. The app has no
`PrivacyInfo.xcprivacy`. If you add one, declare
`NSPrivacyCollectedDataTypeOtherDiagnosticData` with the same linked and
tracking answers and the App Functionality purpose.
