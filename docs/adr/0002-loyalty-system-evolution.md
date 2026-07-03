# ADR-0002: Loyalty system — keep it on `Client`, extend it additively as a premium tier

**Status:** Proposed
**Date:** 2026-07-03
**Deciders:** Luis (solo developer)

## Context

Loyalty **already ships**, on the `Client`:

- `Client.swift:39 var loyaltyPoints: Int = 0`; `Visit.swift:26 var loyaltyPointsChange: Int = 0`.
- `Features/Loyalty/LoyaltyEngine.swift` — `calculatePoints(for:)` is **hardcoded 1 pt/$1**
  (banker's rounding on `Decimal`).
- `Features/Loyalty/LoyaltyService.swift` — an `@ModelActor` that accrues on the owning client
  (`visit.pet?.owner`) and does basic `redeemPoints`.
- Accrual is wired into checkout via `VisitRepository.applyPoints(for: visit)`.

There is **no** `LoyaltyConfig`, **no** rewards catalog, **no** `LoyaltyHistory` audit log, and
**no** milestone logic. The RTF proposes adding all of these — but in a form that conflicts with
the shipped design in three ways:

1. It moves `loyaltyPoints` onto **Pet** (with a `LoyaltyHistory` relationship). The app accrues
   to **Client**, and the Android port mirrors that. Two owners of "points" is a data-integrity bug.
2. It introduces a flat **"20 points/visit → 100"** rule that contradicts the shipped
   **per-dollar** rule.
3. Every proposed model uses `@Attribute(.unique) id`, which the codebase explicitly forbids
   under CloudKit (`VisitItem.swift:17`).

## Decision

**Keep points on `Client`. Extend the system additively**, and expose the richer surface as a
**premium (subscription-gated) tier** per [ADR-0001](0001-monetization-subscription-trial.md):

1. Replace the hardcoded rate with a **`LoyaltyConfig`** model (`Decimal pointsPerDollar`,
   `Int redemptionThreshold`); `LoyaltyEngine.calculatePoints` reads it instead of the literal 1.
2. *(Optional, if the audit/catalog UX is wanted)* add **`LoyaltyHistory`** (earned/redeemed
   ledger, related to `Client`) and a **`LoyaltyReward`** catalog.
3. **Reject** the Pet-based rewrite and the flat "20/visit" default. If a flat/per-visit mode is
   desired, express it as a `LoyaltyConfig` mode — not a second source of truth.
4. **No `@Attribute(.unique)`** on any new model (CloudKit). Use a plain `var id: UUID = UUID()`.
5. Every new model lands under a **V2 schema** per [ADR-0003](0003-swiftdata-migration-discipline.md).

## Options Considered

### Option A: Keep the shipped Client-scalar loyalty, add nothing
**Pros:** zero risk, zero migration. **Cons:** leaves the genuinely useful ideas (configurable
rate, reward catalog, audit trail) on the table; no premium surface to justify the subscription.

### Option B: Keep Client-based; add `LoyaltyConfig` (+ optional history/catalog) additively (chosen)
| Dimension | Assessment |
|-----------|------------|
| Data integrity | One owner of points (`Client`) — no ambiguity. |
| Migration | Additive; new models via V2 (ADR-0003). |
| Product value | Configurable rate + catalog + audit = a real premium tier. |
| CloudKit | Compatible (no `.unique`, relationships optional/defaulted). |

**Pros:** preserves the working accrual path (`VisitRepository.applyPoints`); adds the RTF's good
ideas without its conflicts; gives [ADR-0001](0001-monetization-subscription-trial.md) something
to gate. **Cons:** requires a V2 schema + CloudKit prod deploy for the new models.

### Option C: Adopt the RTF's Pet-based `loyaltyPoints` + `LoyaltyHistory` verbatim
**Cons:** two owners of "points" (Pet vs Client) — a correctness bug; contradicts checkout
accrual and Android parity; `@Attribute(.unique)` breaks CloudKit; caused the RTF's own data-loss
scare. **Rejected.**

## Trade-off Analysis

The RTF's *ideas* (make the rate configurable, show an audit trail, offer a reward catalog with a
satisfying badge) are good and worth building. Its *implementation* is where it goes wrong —
re-homing points onto `Pet` and re-deriving models that already exist. The cheapest correct path
is to treat the shipped Client-based engine as the foundation and layer configuration and catalog
**on top of it**, so the accrual code (`LoyaltyService.applyPoints`) and the checkout integration
keep working unchanged; only `LoyaltyEngine`'s rate source moves from a literal to `LoyaltyConfig`.

Which points attach to *Pet* vs *Client* is not a style choice — the whole checkout accrual path,
the summaries, and the Android port assume `Client`. Moving them is a data migration and a
semantic change for no benefit (a client with three pets should pool loyalty, not split it).

## Consequences

- **Easier:** the premium "Loyalty Management Suite" (rate config, reward catalog, dashboard)
  becomes a clean subscription-gated feature; basic accrual continues for all users during trial.
- **Harder:** adding `LoyaltyConfig`/`LoyaltyHistory`/`LoyaltyReward` is a **structural** schema
  change → triggers the full V2 discipline (ADR-0003) *and* a CloudKit production schema deploy.
- **Revisit:** the animated `LoyaltyPointsBadge` / `CheckoutConfirmationSheet` from the RTF are
  fine as *view-layer* additions (no schema impact) — adopt them separately once the data layer
  lands. Note the RTF badge snippet uses `DispatchQueue.main.mainActor.asyncAfter` (not a real
  API); rewrite with `Task { try? await Task.sleep(...) }` or a `withAnimation` completion.

## Action Items

1. [ ] Add `LoyaltyConfig` (`pointsPerDollar: Decimal = 1`, `redemptionThreshold: Int = 100`);
       make `LoyaltyEngine.calculatePoints` read it. Plain `UUID` id, no `.unique`.
2. [ ] *(If adopting catalog/audit)* add `LoyaltyHistory` (→ `Client`, optional relationship) and
       `LoyaltyReward`; land all new models as **V2** per ADR-0003.
3. [ ] Keep accrual in `VisitRepository.applyPoints` / `LoyaltyService`; do **not** add points to `Pet`.
4. [ ] Gate the management/config/catalog UI behind the subscription entitlement (ADR-0001);
       leave basic accrual ungated during trial.
5. [ ] Port the RTF badge/sheet UI as pure views afterward, fixing the non-API dispatch calls.
