# CHECKLIST

## Phase 1: Forensic Cleanup

- [x] Confirmed `xcodebuildmcp`/`mcpbridge` are not installed on PATH, so no MCP main-thread attach or hierarchy dump was available in this shell.
- [x] Checked available Xcode/simulator tooling for view hierarchy dump support.
- [x] Audited `RootView`, `ContentView`, `DashboardView`, and `InsightsView` for tab-bar hit-test blockers.
- [x] Identified the first-sync and privacy screens as intentional full-screen overlays; UI test launch flags bypass first-sync so they do not mask tap regressions.
- [x] Hardened Dashboard-to-Insights entry points with explicit content shapes and accessibility identifiers.
- [x] Ensured the Insights mesh background is non-interactive so it cannot intercept tab or scroll gestures.
- [x] Verified Insights data work remains off the main path through `InsightsActor`.
- [x] Fixed Dashboard pet-card navigation by sending the UUID payload expected by `ContentView.handleNavigation`.
- [x] Added UI automation coverage for the Dashboard revenue KPI Insights button.
- [x] Verified `dashboard.quickAction.reports` and `dashboard.kpi.revenueInsights` both navigate to Insights through XCUI taps.
- [x] Verified `InsightsUITests` for load, scroll, period switching, export visibility, and pull-to-refresh responsiveness.
- [x] Verified `InsightsViewModelTests` and `InsightsAggregationTests` for actor-backed aggregation and revenue refresh behavior.
- [x] Added actionable Insights drilldowns for revenue, average visit value, and retention.
- [x] Added lapsed-client detection with message and schedule recall actions.
- [x] Added service profitability, forecast, comparison-window, CSV export, and data-quality sections.

## Phase 2: Financial Hardening & Sync Integrity

- [x] Audited production money models and confirmed `Payment.amount`, `Visit.total`, `VisitItem.unitPrice`, `Service.basePrice`, and `DaySummary.revenue` persist as `Decimal`.
- [x] Reworked `RecentHistoryViewModel` background snapshots and summaries to keep revenue as `Decimal` end-to-end instead of converting totals through `Double`.
- [x] Added a recent-history regression test for `$0.10 + $0.20 == $0.30` to catch binary floating-point drift.
- [x] Replaced remaining production inventory Decimal defaults that used floating literals with fully qualified `Decimal` defaults.
- [x] Cleaned unit-test and quality-control money fixtures so fractional currency uses string-backed `Decimal` values and whole-dollar values use integer Decimal construction.
- [x] Refactored lapsed-client recall scheduling out of `InsightsView` main-context saves into `RecallSchedulingActor`.
- [x] Constructed the recall scheduler off-main from the button action to avoid SwiftData main-queue actor warnings.
- [x] Hardened `SyncConflictActor` with idempotent note merging, normalized tag set merging, deterministic tag order, and no-op save suppression.
- [x] Added actor tests for recall appointment creation and idempotent sync conflict reconciliation.
- [x] Verified app build after Phase 2 changes.
- [x] Verified focused unit coverage for Decimal money math, formatting, inventory, recent history, checkout payment reconciliation, recall scheduling, and sync conflict reconciliation.

## Phase 3: Atomic Integrity & Sync Observability

- [x] Confirmed checkout draft recovery already exists through `CheckoutDraftStore` with atomic JSON writes off the main thread.
- [x] Confirmed checkout persistence uses `CheckoutTransactionActor` with idempotency keys and audit transaction status.
- [x] Confirmed CloudKit observability already exists through `CloudKitMonitor`, diagnostics UI, status popovers, remote-push handling, and CKError-aware messages.
- [x] Added recall scheduling coverage through `RecallSchedulingActorTests`.
- [x] Surfaced restored checkout drafts in the UI with an explicit recovery banner instead of silent-only state hydration.
- [x] Added lightweight photo-presence metadata to checkout drafts so recovery can warn when before/after photos must be re-picked after an interruption.
- [x] Fixed checkout bootstrap autosave so opening the wizard no longer overwrites an existing draft before restoration completes.

## Phase 4: Motion & Visual System

- [x] Confirmed global `MotionSystem` already provides snappy, bouncy, fluid, press-scale, reduced-motion, low-power, and thermal-aware animation primitives.
- [x] Confirmed Insights uses a 3x3 `MeshGradient` background with a non-interactive hit-test surface.
- [x] Confirmed revenue and KPI surfaces use `.contentTransition(.numericText())`.
- [x] Confirmed pet/client profile surfaces already use `matchedGeometryEffect` hero transitions.

## Phase 5: Scale & Maintenance

- [x] Upgraded maintenance from launch-only cleanup to `BGProcessingTask` registration and scheduling.
- [x] Scheduled the janitor task for Sunday 3 AM using `PartnerShipWithMedia.Pawtrackr.maintenance`.
- [x] Added `BGTaskSchedulerPermittedIdentifiers` and `processing` background mode to the iOS Info.plist.
- [x] Kept launch-time maintenance as a fallback if iOS does not deliver the background task.
- [x] Janitor now rebuilds summaries and prunes old/downsampled photos in a detached background context.
- [x] Verified Info.plist syntax with `plutil`.
- [x] Verified app build after background task integration.

## Phase 6: Bilingual Coverage

- [x] Audited the localization baseline and confirmed `en`, `es`, and `es-419` string tables already exist.
- [x] Identified the main bilingual gaps as hardcoded English in shared shell views, Clients, Checkout, and model-backed display labels.
- [x] Localized shared macOS-visible shell surfaces: tabs, sidebar sections, split-view placeholder, menu bar extra, edit-client sheet, and recent-history chrome.
- [x] Localized Clients flow copy: delete confirmation, notifications, filter/sort labels, empty states, context menus, and refresh affordances.
- [x] Localized Checkout flow copy across both `CheckoutView` and `CheckoutViewModel`, including recovery banner, step titles, payment review, summaries, and receipt states.
- [x] Localized model-backed labels for payment methods, species, pet gender, grooming frequency, and behavior tags so English does not leak through derived UI.
- [x] Localized Insights dashboard sections, CSV export headings, recall scheduling messages, forecast labels, data-quality findings, and drilldown sheets.
- [x] Localized onboarding steps, validation, biometric messaging, business profile setup, regional setup, PIN setup, and demo-data/fresh-start choices.
- [x] Localized remaining Dashboard, Visit Detail, and Transformation copy, including accessibility labels and share/export surfaces.
- [x] Added the new bilingual keys to `en`, `es`, and `es-419` string tables and verified all three files with `plutil -lint`.
- [x] Verified a clean macOS build after the bilingual pass.

## Phase 7: macOS Adaptive Workspace

- [x] Confirmed the existing root shell already preserves iPhone `TabView` navigation and iPad split-view behavior.
- [x] Revised macOS back to a calmer two-column `NavigationSplitView` after the three-column workspace felt crowded.
- [x] Added a macOS-only `NSVisualEffectView` bridge using `.behindWindow` and `.underWindowBackground` for native translucent desktop material.
- [x] Removed the secondary workspace column so the selected feature owns the main canvas without duplicated controls.
- [x] Kept extended Mac card hover behavior with subtle spring scale.
- [x] Set the Mac main window to hidden title bar, unified toolbar, content-based minimum sizing, and a larger default size.
- [x] Added global Mac keyboard commands for New Client (`Command-N`), Insights (`Command-I`), and Clients (`Command-F`).
- [x] Localized the new macOS command and menu bar labels in `en`, `es`, and `es-419`.
- [x] Verified all localization tables with `plutil -lint`.
- [x] Verified macOS and generic iOS Simulator builds after the adaptive shell pass.

## Phase 8: iPad Interaction & Visit Detail Polish

- [x] Added an explicit `NavigationSplitViewVisibility` binding for iPad/macOS split-view state.
- [x] Replaced passive iPad sidebar selection rows with explicit full-row buttons so swiped-open sidebar items remain tappable.
- [x] Collapsed the iPad sidebar back to detail when selecting from an overlay-style sidebar state.
- [x] Reworked `VisitDetailView` with an iPad-specific centered canvas and organized two-column detail layout.
- [x] Moved iPad checkout action into the payment card instead of a cluttered bottom bar on wide iPad layouts.
- [x] Verified generic iOS Simulator and macOS builds after the iPad fixes.

## Phase 9: Multi-Device Shop Sync Hardening

- [x] Added deterministic `Visit.sessionToken` values in `YYYY-MM-DD_<petUUID>` format and backfilled existing visits through migration version `1.0.3`.
- [x] Hardened active visit check-in into an app-level upsert so simultaneous devices reuse the same active visit instead of creating duplicate shop sessions.
- [x] Extended CloudKit local-change tracking with entity names, record UUIDs, and changed-key metadata for compact sync diagnostics.
- [x] Added a persistent offline mutation buffer capped at 40 records per flush batch for weak Wi-Fi and offline shop edits.
- [x] Added remote persistent-store change observation to publish refresh events, reconcile imports, and clear stale UI screens after CloudKit deltas arrive.
- [x] Added `EcosystemStatusBar` to the shared shell for live `SHOP_SYNC_LIVE`, `SHOP_SYNC_UPDATING`, `SHOP_SYNC_OFFLINE`, and attention states across iPhone, iPad, and macOS.
- [x] Updated Clients refresh flow to react to global CloudKit refresh events instead of waiting for manual navigation or pull-to-refresh.
- [x] Strengthened CloudKit import reconciliation to merge duplicate active visits by `sessionToken`, preserving notes, behavior tags, photos, checkout data, and visit items.
- [x] Strengthened client and pet conflict resolution so notes and tag sets merge instead of blindly overwriting property groups.
- [x] Confirmed no localization string-table update was required for this pass; the status bar uses fixed operator sync state codes.
- [x] Added regression coverage for deterministic session tokens, active-visit upsert behavior, duplicate visit reconciliation, and 40-record offline buffer batching.
- [x] Verified focused sync and repository tests: 22 selected tests passed.
- [x] Verified final generic iOS Simulator and macOS builds after the shop sync hardening pass.
