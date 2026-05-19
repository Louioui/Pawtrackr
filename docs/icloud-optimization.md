# iCloud Sync Optimization Guide

For businesses using Pawtrackr with multiple workers sharing a single iCloud account, follow these recommendations to ensure the fastest and most reliable synchronization.

## 1. Device Setup
- **Background App Refresh:** Ensure this is **ON** for Pawtrackr on all iOS devices. This allows silent iCloud pushes to wake the app and sync data even when it's in the background.
- **Low Data Mode:** Ensure this is **OFF**. Low Data Mode can delay or block iCloud synchronization to save data.
- **iCloud Account:** All devices must be signed into the same iCloud account with **iCloud Drive** and **Pawtrackr** toggled **ON** in the iCloud settings.

## 2. Multi-Worker Workflow
- **Real-time Refresh:** Pawtrackr now automatically refreshes the UI when it detects a remote change (e.g., a check-in on another device).
- **Concurrent Edits:** While the app handles concurrent edits by merging properties, try to avoid editing the *exact same field* (like a pet's name) on two devices at the exact same second.
- **Deduplication:** The app "smartly" detects if two devices clicked "Check In" for the same pet at the same time and will automatically merge those visits to prevent duplicates.

## 3. Best Practices
- **Wait for the Green Cloud:** Look for the green checkmark in the iCloud status icon before switching devices. This confirms your local changes have been successfully handed off to iCloud.
- **Manual Sync:** If you are expecting an update and don't see it yet, you can **pull-to-refresh** on the Dashboard to force an immediate iCloud check.
- **Mac App:** Keep the Mac app open on the desktop; it acts as a reliable "anchor" for your business data and will sync changes from workers' iPhones/iPads in real-time.

## 4. Advanced: CloudKit Sharing
For larger teams, we recommend migrating to **CloudKit Sharing**. This allows:
- Each worker to use their own personal Apple ID.
- The business owner to maintain control and see "Who changed what."
- Enhanced security, as workers don't need the owner's iCloud password.
