# ADR-0001: Monetization — auto-renewable subscription with a 7-day intro free trial

**Status:** Accepted (owner decision, 2026-07-03)
**Date:** 2026-07-03
**Deciders:** Luis (solo developer / business owner)

## Context

Pawtrackr ships today with **no monetization** — a grep of the source finds zero `import
StoreKit`, no paywall, no entitlement check, no trial (the only "monthly" strings are grooming
frequencies). The RTF proposes three mutually exclusive models. This ADR records the chosen
model and its architecture.

Forces at play:
- **Local-first / CloudKit.** The app is offline-capable with `.automatic` CloudKit private-DB
  sync (`AppRuntime.allowsICloudSync`). A subscription that carries ongoing sync cost is a
  natural fit — but gating a *local-first* app must never hold the user's own data hostage.
- **App Review.** Apple has **no native free trial for non-consumables**. Time-bombing a
  downloaded app behind a one-time IAP (the RTF's "Keychain 7-day lock") is an App Review
  Guideline **3.1.1** gray area and relies on Keychain-survives-reinstall, which is real but
  **not Apple-guaranteed** (a factory reset or Keychain clear defeats it).
- **Existing gate surface.** `RootView.swift` already orchestrates presentation gates
  (`showOnboarding`, an app-lock via `bypassLockForCurrentSession`). A paywall slots in as a
  parallel entitlement-gated cover with no architectural change.
- **Real identifiers.** Bundle id is `PartnerShipWithMedia.Pawtrackr` (not the RTF's
  `com.partnershipwithmedia.*`).

## Decision

Ship an **auto-renewable subscription** ("Pawtrackr Pro") with a **7-day introductory free
trial**, implemented with **StoreKit 2**, with entitlement checked as a gate in `RootView`.
Reject the Keychain-timed non-consumable and the two-app model.

- **Product:** subscription group `Pawtrackr Pro`; monthly `PartnerShipWithMedia.Pawtrackr.pro.monthly`
  at $29.99 (optionally add an annual SKU later for churn resistance). **7-day free trial** as an
  App Store Connect **Introductory Offer** (free), configured per-product — *not* in code.
- **Entitlement source of truth:** `Transaction.currentEntitlements` + a `Transaction.updates`
  listener started at launch; verify each `VerificationResult`. **No persisted `@Model`** for
  entitlement (keeps the schema untouched — see [ADR-0003](0003-swiftdata-migration-discipline.md));
  cache a last-known-entitlement snapshot in `UserDefaults`/Keychain for offline launch.
- **The trial is user-initiated, not a silent timer.** With a StoreKit introductory offer there is
  **no first-launch countdown** — the user explicitly taps *Start Free Trial* in the purchase
  sheet, StoreKit grants the entitlement at $0, and it lapses after 7 days unless it renews. This
  is precisely the hand-rolled Keychain clock we are *rejecting*. Any "N days left" banner must
  read the **renewal date off the StoreKit transaction**, never a locally computed date.

## Options Considered

### Option A: Auto-renewable subscription + intro free trial (chosen)
| Dimension | Assessment |
|-----------|------------|
| App Review | **Safe** — Apple's blessed path for time-limited trials (StoreKit owns the clock). |
| Revenue | Recurring; funds ongoing CloudKit/maintenance. |
| Complexity | StoreKit 2 subscription states (grace, billing-retry, refund via `Transaction.updates`). |
| Anti-abuse | Handled by Apple (no reinstall-reset hole). |

**Pros:** compliant; no hand-rolled trial timer; recurring revenue matches a data-sync SaaS.
**Cons:** ongoing value-delivery obligation; churn; must handle subscription lifecycle states;
must not hold local data hostage on lapse (see Consequences).

### Option B: Freemium + one-time $29.99 non-consumable unlock
**Pros:** one-time simplicity; Apple-safe if there's *no* time lock (feature-gated, not clock-gated).
**Cons:** no recurring revenue to offset perpetual sync cost; no true time-limited trial.
*Rejected by owner* in favor of recurring revenue.

### Option C: 7-day Keychain-timed trial → one-time non-consumable lock (the RTF blueprint)
**Pros:** matches the RTF; one-time price.
**Cons:** **App Review 3.1.1 risk** (custom time-bomb on a non-consumable); brittle Keychain
anti-abuse (factory reset / Keychain clear resets the trial); hand-rolled date logic incl.
clock-tampering detection. **Rejected.**

### Option D: Separate $19.99 client-side app
**Cons:** fractures the codebase into two apps; client accounts + cross-device point sync; large
scope and UX friction. **Rejected / deferred.**

## Trade-off Analysis

The decisive axis is **App Review compliance for a *time-limited trial***. A true "7 days free,
then pay" trial is only sanctioned by Apple through an auto-renewable subscription's
introductory offer; every non-subscription route to a *timed* trial is a hand-rolled 3.1.1 risk.
Given the owner wants a time-based trial *and* recurring revenue to fund ongoing sync, Option A
dominates: it is the only choice that gets the trial for free (StoreKit-managed) *and* the
recurring revenue, at the cost of subscription-lifecycle complexity Apple's framework already
structures for you.

## Consequences

- **Easier:** no custom trial timer, no clock-tamper detection, no reinstall-reset hole; the
  paywall is a `RootView` cover parallel to onboarding/lock; premium loyalty features
  ([ADR-0002](0002-loyalty-system-evolution.md)) gate cleanly behind one entitlement flag.
- **Harder:** must handle the full subscription lifecycle — trial → active → **grace period /
  billing retry** → expired → **refund/revoke** (all via `Transaction.updates`). Must configure
  App Store Connect products + intro offer, a `.storekit` test config, and sandbox testing.
- **Local-first obligation (critical):** on lapse you **must not lock the user out of their own
  data.** Gate *premium actions and new writes*, but always allow **read-only access + data
  export** of records they already created. Design the gate as "premium features locked," not
  "app bricked." This is both an ethical requirement and reduces refund/review friction.
- **App Review requirements:** a visible **Restore Purchases** control; **Terms of Use (EULA)**
  and **Privacy Policy** links on the paywall; auto-renew disclosure text (price, period, "cancel
  anytime in Settings"). Missing any of these is a common rejection.
- **Free-tier scope is now a product decision:** anyone who hasn't started the trial, or whose
  trial/subscription has lapsed, hits the paywall. Decide whether "free" = read-only/export-only,
  or a thin always-free core. Recommend read-only + export as the floor.

## Action Items

1. [ ] App Store Connect: create subscription group `Pawtrackr Pro`, product
       `PartnerShipWithMedia.Pawtrackr.pro.monthly` ($29.99), add a **7-day free Introductory Offer**.
2. [ ] Add `Features/Subscription/` with an `EntitlementStore` (`@Observable`/`@MainActor`)
       wrapping `Transaction.currentEntitlements` + a launch `Transaction.updates` task; cache the
       last-known entitlement for offline launch (no new `@Model`).
3. [ ] Build `SubscriptionPaywallView` with a *Start Free Trial* primary CTA (subscribe with the
       intro offer); present it from `RootView` as an entitlement-gated cover *after* onboarding,
       mirroring the existing lock gate. Include Restore / Terms / Privacy. Any "days left" banner
       reads the StoreKit renewal date, not a local timer.
4. [ ] Implement lapse behavior: premium locked, **local data stays readable + exportable**.
5. [ ] Add a `Configuration.storekit` file; test trial → renew → lapse → restore in the sandbox.
6. [ ] Gate premium features (loyalty management suite, advanced dashboards/export) on the single
       entitlement flag; keep basic client/pet/visit logging inside the trial and read-after-lapse.
