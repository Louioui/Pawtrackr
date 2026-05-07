# iCloud Validation Checklist

Run this checklist before shipping any build that changes SwiftData models,
CloudKit sync behavior, or iCloud entitlements.

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

## CloudKit Dashboard

- Inspect record types for all SwiftData models.
- Confirm development schema reflects the current build.
- Confirm no unique constraints or unsupported required fields are present.
- Confirm private database indexes support common fields used by CloudKit/SwiftData.
- Deploy schema to production only after the physical-device matrix passes.

## Performance

- Test with at least 2,000 clients, 3,000 pets, 10,000 visits, and photos on older hardware.
- Open Dashboard, Clients, Client Detail, Pet Detail, Checkout, Recent History, Insights, Settings, and iCloud Diagnostics.
- Confirm scrolling remains responsive and app launch does not block on summary rebuilds.
- Confirm memory use stays stable while opening photo-heavy records.
