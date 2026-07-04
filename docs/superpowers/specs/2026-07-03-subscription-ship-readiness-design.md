# Subscription Ship-Readiness Hardening Design

## Context

Pawtrackr now has a StoreKit-backed premium entitlement, a soft launch paywall, and a client-level premium loyalty and rewards flow. Focused tests verify that non-premium users hit the loyalty paywall and premium UI-test launches can adjust points and redeem a reward through `LoyaltyService`.

The next risk is not another feature. It is making the monetization surface reliable enough for TestFlight/App Review and routine QA.

## Goals

- Keep entitlement truth in StoreKit for production launches.
- Keep local data readable and the launch paywall dismissible.
- Make the paywall resilient when StoreKit product loading is slow or unavailable.
- Keep premium test overrides explicitly UI-test-only.
- Improve automated coverage around the paywall and loyalty gate.
- Fix small build warnings if they are directly obvious and low-risk.

## Non-Goals

- No SwiftData schema changes.
- No configurable loyalty/reward models in this pass.
- No App Store Connect changes from code.
- No new subscription products.
- No hard lock that blocks access to existing local data.

## Design

### Paywall State

`SubscriptionPaywallView` should model the subscription product as a small UI state instead of relying on `product == nil` alone. The visible states are:

- loading product
- product ready
- product unavailable
- processing purchase or restore
- restore found no active subscription
- purchase or restore failed

The primary subscribe button stays disabled until a product is available. Product-unavailable copy should tell the user the feature is temporarily unavailable, not imply their data is locked.

### Links And Disclosure

Terms of Use and Privacy Policy URLs should move into a small app-owned constants surface. The paywall continues to show restore, auto-renew copy, and price/trial copy derived from StoreKit product data.

### Dismissibility

The paywall keeps an explicit dismiss affordance. Dismissing the launch paywall only suppresses the soft launch sheet for the current app launch. Tapping a premium feature while not entitled still presents the paywall.

### Testability

The existing UI-test-only premium override remains gated behind `AppRuntime.isUITesting`. Existing UI tests should not be blocked by the automatic launch paywall unless a test opts in. Add or extend UI tests for:

- launch paywall can be dismissed when explicitly enabled for a UI test
- non-premium loyalty entry presents the paywall
- premium loyalty entry opens the loyalty flow and can redeem a reward

### Warning Cleanup

Investigate the existing `ContentView.swift:307` warning. If the fix is a local simplification with no behavior ambiguity, include it. If it requires broader navigation behavior decisions, leave it for a separate pass.

## Verification

- `git diff --check`
- focused iOS simulator tests for subscription/loyalty/client-detail flows
- native macOS build for platform availability regressions
- iOS simulator build or test through XcodeBuildMCP

## Rollout Notes

This pass should not affect production entitlement decisions except for clearer paywall states and an explicit dismiss button. UI-test overrides must remain unreachable without the UI-testing launch argument or environment.
