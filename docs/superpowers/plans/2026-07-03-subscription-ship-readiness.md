# Subscription Ship-Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden Pawtrackr's subscription/paywall surface for App Review, QA, and StoreKit failure cases.

**Architecture:** Keep production entitlement state StoreKit-owned through `EntitlementStore`. Make `SubscriptionPaywallView` own explicit product-loading UI state, while app constants own legal URLs. Keep all premium overrides gated behind UI-test launch checks.

**Tech Stack:** SwiftUI, StoreKit 2, XCTest UI tests, XcodeBuildMCP simulator test/build flow, native macOS `xcodebuild`.

---

### File Structure

- Create: `Pawtrackr/App/AppLinks.swift` for app-owned legal/support URLs.
- Modify: `Pawtrackr/Features/Subscription/SubscriptionPaywallView.swift` for paywall state, links, button identifiers, and resilient copy.
- Modify: `PawtrackrUITests/LoyaltyUITests.swift` for launch-paywall dismiss coverage.
- Modify: `Pawtrackr/App/ContentView.swift` to remove the known always-true deferral branch if still present.
- Keep: `Pawtrackr/App/AppRuntime.swift`, `Pawtrackr/App/RootView.swift`, and `Pawtrackr/Features/Subscription/EntitlementStore.swift` UI-test-only entitlement controls as already scoped.

### Task 1: App-Owned Legal Links

- [ ] **Step 1: Add constants**

Create `Pawtrackr/App/AppLinks.swift`:

```swift
import Foundation

enum AppLinks {
    static let termsOfUse = URL(string: "https://pawtrackr.app/terms")!
    static let privacyPolicy = URL(string: "https://pawtrackr.app/privacy")!
}
```

- [ ] **Step 2: Wire paywall links**

In `SubscriptionPaywallView.legalFootnote`, replace inline `URL(string:)!` calls with:

```swift
Link("Terms of Use", destination: AppLinks.termsOfUse)
Text(verbatim: "·").foregroundStyle(.secondary)
Link("Privacy Policy", destination: AppLinks.privacyPolicy)
```

### Task 2: Explicit Product Loading State

- [ ] **Step 1: Add state enum**

In `SubscriptionPaywallView`, add:

```swift
private enum ProductLoadState: Equatable {
    case loading
    case ready
    case unavailable
}
```

Then replace the nullable-product-only UI state with:

```swift
@State private var product: Product?
@State private var productLoadState: ProductLoadState = .loading
```

- [ ] **Step 2: Make offer copy stateful**

Update `priceHeadline` so loading and unavailable states are distinct:

```swift
private var priceHeadline: String {
    switch productLoadState {
    case .loading:
        return String(localized: "subscription.paywall.loading_price",
                      defaultValue: "Loading subscription…")
    case .unavailable:
        return String(localized: "subscription.paywall.unavailable",
                      defaultValue: "Subscription is temporarily unavailable.")
    case .ready:
        guard let product else {
            return String(localized: "subscription.paywall.unavailable",
                          defaultValue: "Subscription is temporarily unavailable.")
        }
        let perMonth = String(
            format: String(localized: "subscription.paywall.price_per_month",
                           defaultValue: "%@ / month"),
            product.displayPrice
        )
        guard hasFreeTrial, let offer = product.subscription?.introductoryOffer else {
            return perMonth
        }
        let trial = Self.periodText(offer.period)
        return String(
            format: String(localized: "subscription.paywall.trial_then_price",
                           defaultValue: "%@ free, then %@"),
            trial, perMonth
        )
    }
}
```

- [ ] **Step 3: Update loading action behavior**

Add:

```swift
private var canStartPurchase: Bool {
    productLoadState == .ready && product != nil && !isProcessing
}
```

Then change the subscribe button disabled state to:

```swift
.disabled(!canStartPurchase)
```

### Task 3: StoreKit Load Failure Copy

- [ ] **Step 1: Update product loading**

Replace `loadProduct()` with:

```swift
private func loadProduct() async {
    productLoadState = .loading
    do {
        product = try await Product.products(for: [EntitlementStore.monthlyProductID]).first
        if product == nil {
            productLoadState = .unavailable
            logger.warning("No product returned for \(EntitlementStore.monthlyProductID, privacy: .public) — is the StoreKit config selected in the scheme?")
        } else {
            productLoadState = .ready
        }
    } catch {
        product = nil
        productLoadState = .unavailable
        errorMessage = String(
            localized: "subscription.paywall.load_failed",
            defaultValue: "We could not load the subscription right now. Please try again later."
        )
        logger.error("Failed to load product: \(error.localizedDescription, privacy: .public)")
    }
}
```

- [ ] **Step 2: Guard purchases**

At the top of `startPurchase()`, add:

```swift
guard productLoadState == .ready, product != nil else {
    errorMessage = String(
        localized: "subscription.paywall.unavailable_detail",
        defaultValue: "Subscription is temporarily unavailable. Your local data remains accessible."
    )
    return
}
```

### Task 4: UI Regression Coverage

- [ ] **Step 1: Add launch paywall test**

In `PawtrackrUITests/LoyaltyUITests.swift`, add:

```swift
func testAutomaticLaunchPaywallCanBeDismissed() throws {
    launch(premium: false, automaticPaywall: true)

    XCTAssertTrue(app.staticTexts["Elevate Pawtrackr"].waitForExistence(timeout: 8))
    let dismiss = app.buttons["subscriptionPaywall.dismiss"]
    XCTAssertTrue(dismiss.waitForHittable(timeout: 6))
    dismiss.tap()

    XCTAssertTrue(waitForDashboard(), "Dashboard should remain usable after dismissing the launch paywall.")
}
```

Update helper signature:

```swift
private func launch(premium: Bool, automaticPaywall: Bool = false) {
    app = XCUIApplication()
    app.launchArguments = [
        "-pawtrackr-ui-testing",
        "-AppleLanguages", "(en)",
        "-AppleLocale", "en_US"
    ]
    app.launchEnvironment["PAWTRACKR_UI_TESTING"] = "1"
    if premium {
        app.launchEnvironment["PAWTRACKR_UI_TESTING_PREMIUM"] = "1"
    }
    if automaticPaywall {
        app.launchEnvironment["PAWTRACKR_UI_TESTING_AUTOMATIC_PAYWALL"] = "1"
    }
    app.launch()
}
```

### Task 5: Warning Cleanup

- [ ] **Step 1: Simplify deferral branch**

In `ContentView.openWalkthroughDemoClientDetail()`, remove the `needsDeferral` variable and the unreachable `guard needsDeferral else` branch. Keep the deferred task:

```swift
Task { @MainActor in
    try? await Task.sleep(for: .milliseconds(350))
    guard walkthrough.isActive,
          walkthrough.currentStep?.route == .demoClientDetail else { return }
    performDemoClientDetailNavigation()
}
```

### Task 6: Verification

- [ ] **Step 1: Whitespace check**

Run:

```bash
git diff --check
```

Expected: exit 0 with no output.

- [ ] **Step 2: Focused iOS simulator tests**

Run through XcodeBuildMCP:

```text
test_sim extraArgs:
-only-testing:PawtrackrTests/LoyaltyServiceTests
-only-testing:PawtrackrTests/LoyaltyRewardCatalogTests
-only-testing:PawtrackrUITests/LoyaltyUITests
-only-testing:PawtrackrUITests/ClientDetailUITests/testOpeningSeededClientShowsDetailView
```

Expected: all selected tests pass.

- [ ] **Step 3: Native macOS build**

Run:

```bash
xcodebuild -project Pawtrackr.xcodeproj -scheme Pawtrackr -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/PawtrackrMacDerivedData build
```

Expected: `** BUILD SUCCEEDED **`.
