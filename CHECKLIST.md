# Pawtrackr Architectural Overhaul Checklist

## Infrastructure Foundation
- [ ] Establish feature-driven directory structure
- [ ] Initialize `CHECKLIST.md` (Current)
- [ ] Stable repository caching (git update-index --refresh)

## Thread & Performance Architecture
- [ ] Forensic trace of Thread 1 rendering
- [ ] Isolate data operations to `@ModelActor` (BackgroundAnalyticsJanitor, RevenueActor, TransactionBackupJanitor)
- [ ] Implement adaptive navigation (NavigationSplitView)
- [ ] Apply macOS glassmorphic UI enhancements

## Data & Sync Sovereignty
- [ ] Replace floating-point types with `Decimal` for financial precision
- [ ] Implement `ShopSyncCoordinator` for remote change tracking
- [ ] Build offline shadow transaction ring-buffer
- [ ] Secure sensitive data with hardware-backed encryption
- [ ] Implement `CKErrorUserDidResetEncryptedDataKey` self-healing
- [ ] Optimize database indexing and external storage for binary blobs

## UI/UX & Localization
- [ ] Migrate to `Localizable.xcstrings`
- [ ] Integrate global keyboard shortcuts
- [ ] Add spring-driven micro-interactions
