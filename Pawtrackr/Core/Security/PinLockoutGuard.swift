//
//  PinLockoutGuard.swift
//  Pawtrackr
//
//  Persistent brute-force throttle for the app PIN.
//
//  WHY THIS EXISTS
//  The PIN lock screen previously tracked failed attempts in SwiftUI
//  `@State`. That state lives only as long as the view (and the process):
//  an attacker could try the threshold number of PINs, force-quit the app,
//  relaunch, and get a fresh batch of attempts — repeating indefinitely and
//  defeating the lockout entirely. This guard moves the counters into the
//  Keychain so the lockout survives force-quit, app relaunch, AND reinstall
//  (Keychain items outlive app deletion on iOS), which is the only place a
//  local-PIN throttle can be enforced without a server.
//
//  POLICY
//  Attempts 1...4 are free. The 5th consecutive failure starts a lockout that
//  escalates with continued failures and caps at 15 minutes — honoring the
//  "5 attempts, up to a 15-minute lockout" intent while not hard-locking a
//  legitimate user who fat-fingers a few digits. A successful unlock (PIN or
//  biometric) clears everything.
//
//  KNOWN LIMITATION
//  `lockoutUntil` is an absolute wall-clock deadline, so a user who manually
//  moves the device clock forward can expire a lockout early. That requires
//  changing system time (which disrupts the whole device) and is the standard
//  trade-off for an offline, server-less throttle; a monotonic clock would not
//  survive reboot. Documented intentionally rather than silently accepted.
//

import Foundation

/// Keychain-backed, force-quit-proof throttle for PIN unlock attempts.
enum PinLockoutGuard {
    /// Consecutive failures allowed before a lockout begins. The Nth failure
    /// (N == threshold) triggers the first cooldown.
    static let threshold = 5

    /// Escalating cooldowns, indexed by `failedAttempts - threshold`. Caps at
    /// the final value (15 minutes), the ceiling the product requirement asks
    /// for. Kept deliberately short at first so an honest mistype isn't punished
    /// like an attack.
    private static let ladder: [TimeInterval] = [
        60,    // 5th failure  → 1 minute
        120,   // 6th failure  → 2 minutes
        300,   // 7th failure  → 5 minutes
        900    // 8th+ failure → 15 minutes (cap)
    ]

    private static let attemptsKey = "pinFailedAttempts"
    private static let lockoutUntilKey = "pinLockoutUntil"

    /// Number of consecutive failed attempts recorded so far.
    static var failedAttempts: Int {
        Int(KeychainStorage.string(forKey: attemptsKey) ?? "") ?? 0
    }

    /// Absolute time the current lockout ends, or `nil` when not locked out.
    static var lockoutUntil: Date? {
        guard let raw = KeychainStorage.string(forKey: lockoutUntilKey),
              let epoch = TimeInterval(raw) else { return nil }
        return Date(timeIntervalSince1970: epoch)
    }

    /// True while a cooldown is in effect.
    static var isLockedOut: Bool {
        guard let until = lockoutUntil else { return false }
        return Date() < until
    }

    /// Seconds remaining in the current lockout (0 when not locked out).
    static var remaining: TimeInterval {
        guard let until = lockoutUntil else { return 0 }
        return max(0, until.timeIntervalSinceNow)
    }

    /// Records one failed attempt and, once the threshold is reached, opens (or
    /// extends) the lockout window. Returns the new lockout deadline if one is
    /// now active, else `nil`.
    @discardableResult
    static func registerFailure() -> Date? {
        let attempts = failedAttempts + 1
        KeychainStorage.set(String(attempts), forKey: attemptsKey)

        guard attempts >= threshold else { return nil }
        let rung = min(attempts - threshold, ladder.count - 1)
        let until = Date().addingTimeInterval(ladder[rung])
        KeychainStorage.set(String(until.timeIntervalSince1970), forKey: lockoutUntilKey)
        return until
    }

    /// Clears all failure/lockout state. Call on any successful unlock.
    static func reset() {
        KeychainStorage.remove(forKey: attemptsKey)
        KeychainStorage.remove(forKey: lockoutUntilKey)
    }
}
