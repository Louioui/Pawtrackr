//
//  LoyaltyTier.swift
//  Pawtrackr
//
//  Loyalty tier ladder derived from lifetime visit-earned points.
//
//  Tiers are COMPUTED, never persisted: the source of truth is the sum of
//  positive `Visit.loyaltyPointsChange` values, so tier state can't drift
//  from CloudKit merges and requires no schema change. Redemptions and
//  manual adjustments intentionally do NOT affect tier — spending points
//  must never demote a client.
//

import Foundation

enum LoyaltyTier: String, CaseIterable, Sendable {
    case bronze
    case silver
    case gold
    case platinum

    /// Minimum lifetime visit-earned points required to hold this tier.
    var threshold: Int {
        switch self {
        case .bronze: 0
        case .silver: 500
        case .gold: 1_500
        case .platinum: 3_500
        }
    }

    /// Earn multiplier applied to base checkout points, expressed as an
    /// integer percentage so point math stays deterministic (no floating
    /// point anywhere near loyalty balances).
    var earnMultiplierPercent: Int {
        switch self {
        case .bronze: 100
        case .silver: 110
        case .gold: 125
        case .platinum: 150
        }
    }

    var displayName: String {
        switch self {
        case .bronze: "Bronze"
        case .silver: "Silver"
        case .gold: "Gold"
        case .platinum: "Platinum"
        }
    }

    /// Human-readable earn rate, e.g. "1.25×".
    var earnRateText: String {
        let whole = earnMultiplierPercent / 100
        let fraction = earnMultiplierPercent % 100
        guard fraction != 0 else { return "\(whole)×" }
        let fractionText = fraction % 10 == 0 ? "\(fraction / 10)" : String(format: "%02d", fraction)
        return "\(whole).\(fractionText)×"
    }

    /// The next tier up the ladder, or nil at the top.
    var next: LoyaltyTier? {
        switch self {
        case .bronze: .silver
        case .silver: .gold
        case .gold: .platinum
        case .platinum: nil
        }
    }
}
