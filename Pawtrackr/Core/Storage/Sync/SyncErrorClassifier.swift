//
//  SyncErrorClassifier.swift
//  Pawtrackr
//
//  Pure classification of CloudKit mirroring errors. An export failure arrives
//  as one outer error (usually CKError.partialFailure, sometimes wrapped in a
//  Cocoa error) and the reason that matters sits in the per-record errors
//  inside it. Reading only the outer code is how a Production schema rejection
//  ended up telling groomers "They'll retry shortly".
//

import Foundation
import CloudKit

nonisolated enum SyncErrorClassifier {
    enum UserActionKind: String, Codable, Hashable, Sendable {
        case quotaExceeded
        case notAuthenticated
        case accountTemporarilyUnavailable
        case userDeletedZone
    }

    enum Disposition: Codable, Hashable, Sendable {
        case transient
        case userActionable(UserActionKind)
        case schemaRejected
        case limitExceeded
        /// Conflicts the mirroring delegate resolves on its own.
        case benign
        /// Mirroring setup reported "no iCloud account" (134400) while
        /// CKContainer says the account is available, so nothing will upload
        /// until the next launch even though the groomer is signed in.
        case setupFailedWhileSignedIn
        case unknown

        /// Stable, content-free name for logs and telemetry.
        var diagnosticName: String {
            switch self {
            case .transient: return "transient"
            case .userActionable(let kind): return "userActionable.\(kind.rawValue)"
            case .schemaRejected: return "schemaRejected"
            case .limitExceeded: return "limitExceeded"
            case .benign: return "benign"
            case .setupFailedWhileSignedIn: return "setupFailedWhileSignedIn"
            case .unknown: return "unknown"
            }
        }
    }

    struct Classification: Codable, Hashable, Sendable {
        let disposition: Disposition
        let innermostDomain: String
        let innermostCode: Int
        /// The server's own wording when CloudKit supplied one. It can name
        /// record types and record IDs, so it belongs in on-device diagnostics
        /// only, never in anything sent off the device.
        let serverMessage: String?

        /// True when retrying alone won't clear it: the schema, the payload,
        /// the account or the groomer has to change first. `.unknown` is false
        /// because nothing proves it's permanent; the failure streak decides
        /// whether it escalates.
        var isPermanent: Bool {
            switch disposition {
            case .schemaRejected, .limitExceeded, .setupFailedWhileSignedIn, .userActionable:
                return true
            case .transient, .benign, .unknown:
                return false
            }
        }

        /// Localization key the UI can map to a message. `nil` means there is
        /// nothing to tell the groomer. Only `.transient` maps to the "retry
        /// shortly" copy, because that promise is true only when every inner
        /// error is transient.
        var userMessageKey: String? {
            switch disposition {
            case .transient:
                return SyncErrorClassifier.isNetworkCode(domain: innermostDomain, code: innermostCode)
                    ? "cloudkit.error.network"
                    : "cloudkit.error.partial"
            case .userActionable(.quotaExceeded): return "cloudkit.error.quota"
            case .userActionable(.notAuthenticated): return "cloudkit.error.signed_out"
            case .userActionable(.accountTemporarilyUnavailable): return "cloudkit.error.account_temporarily_unavailable"
            case .userActionable(.userDeletedZone): return "cloudkit.error.user_deleted_zone"
            case .schemaRejected: return "cloudkit.error.schema_rejected"
            case .limitExceeded: return "cloudkit.error.limit_exceeded"
            case .setupFailedWhileSignedIn: return "cloudkit.error.setup_failed"
            case .benign: return nil
            case .unknown: return "cloudkit.error.generic"
            }
        }

        /// Same shape as the event log's existing `errorCode` ("CKError.15",
        /// "NSCocoaErrorDomain.134400") so old and new entries read alike.
        var diagnosticCode: String {
            innermostDomain == CKError.errorDomain
                ? "CKError.\(innermostCode)"
                : "\(innermostDomain).\(innermostCode)"
        }
    }

    /// `accountAvailable` is the caller's CKContainer account status. The
    /// mirroring delegate raises 134400 both for a genuinely signed-out device
    /// and for a setup that failed while signed in, and only the account
    /// status tells them apart.
    static func classify(_ error: Error, accountAvailable: Bool) -> Classification {
        var findings: [Finding] = []
        var quotaHints: [Finding] = []
        collect(error, depth: 0, accountAvailable: accountAvailable, findings: &findings, quotaHints: &quotaHints)

        // batchRequestFailed only says "a sibling failed"; letting it vote
        // would bury the sibling that actually explains the failure.
        let dominant = findings.filter { !$0.isCollateral }.min(by: precedes)
        if let dominant, dominant.disposition != .unknown {
            return dominant.classification
        }

        // Codes explained nothing. The daemon sometimes reports quota only in
        // text, so text may lift an unknown result but never overrides a code.
        if let hint = quotaHints.min(by: precedes) {
            return hint.classification
        }
        if let fallback = dominant ?? findings.min(by: precedes) {
            return fallback.classification
        }

        let nsError = error as NSError
        return Classification(
            disposition: .unknown,
            innermostDomain: nsError.domain,
            innermostCode: nsError.code,
            serverMessage: serverMessage(of: nsError)
        )
    }

    // MARK: - Traversal

    private struct Finding {
        let disposition: Disposition
        let domain: String
        let code: Int
        let serverMessage: String?
        let depth: Int
        let isCollateral: Bool

        var classification: Classification {
            Classification(disposition: disposition, innermostDomain: domain, innermostCode: code, serverMessage: serverMessage)
        }
    }

    private enum CodeVerdict {
        case decisive(Disposition)
        case collateral
        case undecided
    }

    private static let maxDepth = 8

    private static func collect(
        _ error: Error,
        depth: Int,
        accountAvailable: Bool,
        findings: inout [Finding],
        quotaHints: inout [Finding]
    ) {
        let nsError = error as NSError

        func finding(_ disposition: Disposition, collateral: Bool = false) -> Finding {
            Finding(
                disposition: disposition,
                domain: nsError.domain,
                code: nsError.code,
                serverMessage: serverMessage(of: nsError),
                depth: depth,
                isCollateral: collateral
            )
        }

        switch verdict(for: nsError, accountAvailable: accountAvailable) {
        case .decisive(let disposition):
            findings.append(finding(disposition))
            return
        case .collateral:
            findings.append(finding(.unknown, collateral: true))
            return
        case .undecided:
            break
        }

        if mentionsQuota(nsError) {
            quotaHints.append(finding(.userActionable(.quotaExceeded)))
        }

        let nested = depth + 1 < maxDepth ? children(of: nsError) : []
        guard !nested.isEmpty else {
            findings.append(finding(.unknown))
            return
        }
        for child in nested {
            collect(child, depth: depth + 1, accountAvailable: accountAvailable, findings: &findings, quotaHints: &quotaHints)
        }
    }

    /// One pass over userInfo covers CKPartialErrorsByItemIDKey,
    /// NSUnderlyingErrorKey, NSDetailedErrorsKey and anything else nested,
    /// without visiting the same child twice.
    private static func children(of nsError: NSError) -> [Error] {
        var result: [Error] = []
        for value in nsError.userInfo.values {
            if let nested = value as? Error {
                result.append(nested)
            } else if let nested = value as? [Error] {
                result.append(contentsOf: nested)
            } else if let nested = value as? [AnyHashable: Error] {
                result.append(contentsOf: nested.values)
            }
        }
        return result
    }

    private static func verdict(for nsError: NSError, accountAvailable: Bool) -> CodeVerdict {
        switch nsError.domain {
        case CKError.errorDomain:
            return verdict(forCloudKitCode: nsError.code, nsError: nsError)
        case NSCocoaErrorDomain where nsError.code == 134400:
            return .decisive(accountAvailable ? .setupFailedWhileSignedIn : .userActionable(.notAuthenticated))
        case NSCocoaErrorDomain where nsError.code == 134417 && children(of: nsError).isEmpty:
            // A bare 134417 is "cancelled because there is already a pending
            // request": the queued export still runs, and bursts of saves
            // produce these. One that wraps an error is decided by that error.
            return .decisive(.benign)
        case NSURLErrorDomain where networkURLErrorCodes.contains(nsError.code):
            return .decisive(.transient)
        default:
            return .undecided
        }
    }

    private static func verdict(forCloudKitCode rawCode: Int, nsError: NSError) -> CodeVerdict {
        guard let code = CKError.Code(rawValue: rawCode) else { return .undecided }
        switch code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy,
             .serverResponseLost:
            return .decisive(.transient)
        case .quotaExceeded:
            return .decisive(.userActionable(.quotaExceeded))
        case .notAuthenticated:
            return .decisive(.userActionable(.notAuthenticated))
        case .accountTemporarilyUnavailable:
            return .decisive(.userActionable(.accountTemporarilyUnavailable))
        case .userDeletedZone:
            return .decisive(.userActionable(.userDeletedZone))
        case .invalidArguments:
            return .decisive(.schemaRejected)
        case .serverRejectedRequest:
            // Also returned for reasons unrelated to the schema, so the code
            // alone can't justify "iCloud isn't accepting Pawtrackr's data".
            return mentionsSchemaRejection(nsError) ? .decisive(.schemaRejected) : .undecided
        case .limitExceeded:
            return .decisive(.limitExceeded)
        case .serverRecordChanged:
            return .decisive(.benign)
        case .batchRequestFailed:
            return .collateral
        default:
            return .undecided
        }
    }

    // MARK: - Ranking

    /// Most severe first. `.unknown` outranks `.transient` so a single
    /// unexplained error is enough to stop the UI promising a retry.
    private static func rank(of disposition: Disposition) -> Int {
        switch disposition {
        case .schemaRejected: return 0
        case .limitExceeded: return 1
        case .setupFailedWhileSignedIn: return 2
        case .userActionable(.notAuthenticated): return 3
        case .userActionable(.accountTemporarilyUnavailable): return 4
        case .userActionable(.userDeletedZone): return 5
        case .userActionable(.quotaExceeded): return 6
        case .unknown: return 7
        case .transient: return 8
        case .benign: return 9
        }
    }

    /// Ties go to the deepest error, then the lowest code, so the result
    /// doesn't depend on dictionary order inside partialErrorsByItemID.
    private static func precedes(_ lhs: Finding, _ rhs: Finding) -> Bool {
        let lhsRank = rank(of: lhs.disposition)
        let rhsRank = rank(of: rhs.disposition)
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        if lhs.depth != rhs.depth { return lhs.depth > rhs.depth }
        if lhs.code != rhs.code { return lhs.code < rhs.code }
        return lhs.domain < rhs.domain
    }

    // MARK: - Text hints

    private static let networkURLErrorCodes: Set<Int> = [
        URLError.Code.notConnectedToInternet.rawValue,
        URLError.Code.networkConnectionLost.rawValue,
        URLError.Code.timedOut.rawValue,
        URLError.Code.cannotFindHost.rawValue,
        URLError.Code.cannotConnectToHost.rawValue,
        URLError.Code.dnsLookupFailed.rawValue,
        URLError.Code.internationalRoamingOff.rawValue,
        URLError.Code.dataNotAllowed.rawValue
    ]

    fileprivate static func isNetworkCode(domain: String, code: Int) -> Bool {
        if domain == CKError.errorDomain {
            return code == CKError.Code.networkUnavailable.rawValue
                || code == CKError.Code.networkFailure.rawValue
        }
        return domain == NSURLErrorDomain && networkURLErrorCodes.contains(code)
    }

    /// CloudKit keeps the server's wording under this private userInfo key;
    /// the localized description is the fallback that usually embeds it.
    private static let serverDescriptionKey = "ServerErrorDescription"

    private static func serverMessage(of nsError: NSError) -> String? {
        guard nsError.domain == CKError.errorDomain else { return nil }
        let message = (nsError.userInfo[serverDescriptionKey] as? String)
            ?? (nsError.userInfo[NSLocalizedDescriptionKey] as? String)
        guard let message, !message.isEmpty else { return nil }
        return message
    }

    private static func foldedText(of nsError: NSError) -> String {
        let bits = [
            nsError.localizedDescription,
            nsError.localizedFailureReason,
            nsError.localizedRecoverySuggestion
        ].compactMap { $0 } + nsError.userInfo.values.compactMap { $0 as? String }
        return bits.joined(separator: " ").lowercased()
    }

    private static func mentionsQuota(_ nsError: NSError) -> Bool {
        let text = foldedText(of: nsError)
        return text.contains("quotaexceeded")
            || text.contains("quota exceeded")
            || text.contains("storage is full")
    }

    private static func mentionsSchemaRejection(_ nsError: NSError) -> Bool {
        let text = foldedText(of: nsError)
        return text.contains("production schema") || text.contains("cannot create")
    }
}
