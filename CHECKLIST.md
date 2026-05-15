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
