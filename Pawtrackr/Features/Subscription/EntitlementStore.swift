//
//  EntitlementStore.swift
//  Pawtrackr
//
//  Core StoreKit 2 entitlement layer for the Pawtrackr Pro subscription.
//  Owns the app's premium/trial state; the UI reads this store and never talks
//  to StoreKit directly. See docs/adr/0001-monetization-subscription-trial.md.
//

import Foundation
import StoreKit
import OSLog

/// Observable, main-actor source of truth for the user's subscription entitlement.
///
/// Design (per ADR-0001):
/// - **StoreKit is the source of truth.** There is no persisted `@Model` for
///   entitlement, which keeps the SwiftData schema untouched (ADR-0003).
/// - **`Transaction.updates` is monitored for the app's lifetime**, so renewals,
///   trial starts, refunds, and revocations reflect immediately across devices.
/// - **The trial is user-initiated** (a StoreKit introductory offer), never a local
///   timer; `isInTrial` is derived from the entitlement transaction's intro offer.
@MainActor
@Observable
final class EntitlementStore {

    /// The Pawtrackr Pro monthly auto-renewable subscription product identifier.
    /// Must match the App Store Connect product and `Pawtrackr.storekit`.
    static let monthlyProductID = "PartnerShipWithMedia.Pawtrackr.monthly.pro"

    /// Coarse entitlement state the rest of the app gates on.
    enum Status: Equatable, Sendable {
        /// Not yet determined (before the first entitlement check completes).
        case unknown
        /// No active entitlement — the paywall applies (local data stays read/export-only).
        case notEntitled
        /// Active premium access. `inTrial` is true while the intro free trial runs.
        case entitled(inTrial: Bool, expiration: Date?)
    }

    /// Observable entitlement state. Starts `.unknown`; resolved on `start()`.
    private(set) var status: Status = .unknown

    /// True whenever the user has active premium access (paid **or** in trial).
    var isPremium: Bool {
        if case .entitled = status { return true }
        return false
    }

    /// True only while the user is inside the introductory free-trial window.
    var isInTrial: Bool {
        if case .entitled(let inTrial, _) = status { return inTrial }
        return false
    }

    /// When the current entitlement lapses, if known (trial end or paid renewal date).
    var expirationDate: Date? {
        if case .entitled(_, let expiration) = status { return expiration }
        return nil
    }

    private var listener: Task<Void, Never>?
    private var expiryRefresh: Task<Void, Never>?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Pawtrackr",
        category: "entitlement"
    )

    init() {}

    /// Idempotently resolves the current entitlement and begins lifelong transaction
    /// monitoring. Safe to call from multiple scene lifecycles — only the first starts work.
    func start() {
        guard listener == nil else { return }
        if let mockedStatus = AppRuntime.mockedEntitlementStatusForUITesting {
            status = mockedStatus
            return
        }
        listener = Task { [weak self] in
            // Resolve the current entitlement immediately...
            await self?.refresh()
            // ...then keep it live for the app's lifetime.
            for await update in Transaction.updates {
                guard let self else { return }
                await self.process(update)
            }
        }
    }

    /// Cancels transaction monitoring. Primarily for deterministic test teardown;
    /// in the running app the store lives for the whole process.
    func stop() {
        listener?.cancel()
        listener = nil
        expiryRefresh?.cancel()
        expiryRefresh = nil
    }

    /// Recomputes `status` from StoreKit's current entitlements.
    func refresh() async {
        if let mockedStatus = AppRuntime.mockedEntitlementStatusForUITesting {
            status = mockedStatus
            return
        }
        var resolved: Status = .notEntitled
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.productID == Self.monthlyProductID else { continue }
            // Skip refunded/revoked or already-expired entitlements.
            if transaction.revocationDate != nil { continue }
            if let expiration = transaction.expirationDate, expiration <= Date() { continue }
            resolved = .entitled(
                inTrial: transaction.isIntroductoryTrial,
                expiration: transaction.expirationDate
            )
        }
        status = resolved
        armExpiryRefresh()
    }

    /// StoreKit emits NO transaction update when a cancelled subscription
    /// simply lapses at period end, so an entitled app would stay unlocked
    /// past expiry. Schedule a re-resolve just after the known expiration;
    /// each refresh re-arms (or clears) the timer.
    private func armExpiryRefresh() {
        expiryRefresh?.cancel()
        expiryRefresh = nil
        guard case .entitled(_, let expiration) = status, let expiration else { return }
        // Small grace so we re-check after — not exactly at — the boundary.
        let delay = expiration.timeIntervalSinceNow + 2
        guard delay > 0 else { return }
        expiryRefresh = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return // cancelled — a newer refresh owns the schedule now
            }
            await self?.refresh()
        }
    }

    /// Purchases the monthly subscription (with its intro trial, if the user is
    /// eligible). Returns `true` on a verified purchase. The paywall calls this.
    @discardableResult
    func purchaseMonthly() async throws -> Bool {
        guard let product = try await StoreKitTimeout.run({
            try await Product.products(for: [Self.monthlyProductID]).first
        }) else {
            logger.error("Pawtrackr Pro product not found: \(Self.monthlyProductID, privacy: .public)")
            return false
        }
        switch try await product.purchase() {
        case .success(let verification):
            let transaction = try Self.checkVerified(verification)
            await transaction.finish()
            await refresh()
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    /// Restores entitlements — the paywall's "Restore Purchases" action (App Review requirement).
    func restore() async {
        try? await AppStore.sync()
        await refresh()
    }

    // MARK: - Private

    private func process(_ result: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = result else {
            logger.warning("Ignoring unverified transaction update.")
            return
        }
        await transaction.finish()
        await refresh()
    }

    private static func checkVerified(_ result: VerificationResult<Transaction>) throws -> Transaction {
        switch result {
        case .verified(let safe): return safe
        case .unverified(_, let error): throw error
        }
    }
}

// MARK: - Trial detection

private extension Transaction {
    /// True when this entitlement is currently the introductory free trial.
    /// `offer` is available on iOS 17.2+ / macOS 14.2+ — always satisfied by the
    /// project's iOS 18 / macOS 15 deployment targets.
    var isIntroductoryTrial: Bool {
        offer?.type == .introductory
    }
}

// MARK: - Timeout guard

/// Races an async operation against a wall-clock deadline. `Product.products`
/// can hang indefinitely on a throttled network, which would strand the paywall
/// in a permanent loading state with no error and no retry. Wrap only the
/// *fetch* calls — never `product.purchase()`, whose payment sheet legitimately
/// waits on the user.
enum StoreKitTimeout {
    struct TimedOut: LocalizedError, Equatable {
        var errorDescription: String? {
            String(localized: "storekit.timeout",
                   defaultValue: "The App Store did not respond. Please check your connection and try again.")
        }
    }

    static func run<T: Sendable>(
        seconds: Double = 2.0,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw TimedOut()
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw TimedOut() }
            return first
        }
    }
}
