import XCTest
import CloudKit
import CoreData
@testable import Pawtrackr

final class SyncErrorClassifierTests: XCTestCase {

    // MARK: - Partial failures

    func testSchemaRejectionInsidePartialFailureWinsOverBatchSiblings() {
        let schemaMessage = "Cannot create new type CD_LoyaltyConfig in production schema"
        let partial = partialFailure([
            recordID("loyalty-config"): ckError(.serverRejectedRequest, serverMessage: schemaMessage),
            recordID("client-1"): ckError(.batchRequestFailed),
            recordID("pet-1"): ckError(.batchRequestFailed)
        ])

        let result = SyncErrorClassifier.classify(partial, accountAvailable: true)

        XCTAssertEqual(result.disposition, .schemaRejected)
        XCTAssertEqual(result.innermostDomain, CKError.errorDomain)
        XCTAssertEqual(result.innermostCode, CKError.Code.serverRejectedRequest.rawValue)
        XCTAssertEqual(result.serverMessage, schemaMessage)
        XCTAssertTrue(result.isPermanent)
        XCTAssertEqual(result.userMessageKey, "cloudkit.error.schema_rejected")
        XCTAssertEqual(result.diagnosticCode, "CKError.15")
    }

    func testSchemaRejectionIsFoundThroughCocoaWrapper() {
        let partial = partialFailure([
            recordID("loyalty-config"): ckError(
                .serverRejectedRequest,
                serverMessage: "Cannot create new type CD_LoyaltyConfig in production schema"
            ),
            recordID("client-1"): ckError(.batchRequestFailed)
        ])
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134417, userInfo: [NSUnderlyingErrorKey: partial])

        let result = SyncErrorClassifier.classify(wrapped, accountAvailable: true)

        XCTAssertEqual(result.disposition, .schemaRejected)
        XCTAssertEqual(result.innermostCode, CKError.Code.serverRejectedRequest.rawValue)
    }

    func testInvalidArgumentsIsSchemaRejectedByCodeAlone() {
        let partial = partialFailure([
            recordID("visit-1"): ckError(.invalidArguments),
            recordID("client-1"): ckError(.batchRequestFailed)
        ])

        let result = SyncErrorClassifier.classify(partial, accountAvailable: true)

        XCTAssertEqual(result.disposition, .schemaRejected)
        XCTAssertEqual(result.innermostCode, CKError.Code.invalidArguments.rawValue)
    }

    func testServerRejectedRequestWithoutSchemaTextStaysUnknown() {
        let partial = partialFailure([
            recordID("client-1"): ckError(.serverRejectedRequest, serverMessage: "Request failed with http status code 500"),
            recordID("pet-1"): ckError(.batchRequestFailed)
        ])

        let result = SyncErrorClassifier.classify(partial, accountAvailable: true)

        XCTAssertEqual(result.disposition, .unknown)
        XCTAssertEqual(result.innermostCode, CKError.Code.serverRejectedRequest.rawValue)
        XCTAssertFalse(result.isPermanent)
        XCTAssertEqual(result.userMessageKey, "cloudkit.error.generic")
    }

    func testAllTransientPartialFailureIsTransient() {
        let partial = partialFailure([
            recordID("client-1"): ckError(.zoneBusy),
            recordID("client-2"): ckError(.requestRateLimited),
            recordID("pet-1"): ckError(.serviceUnavailable),
            recordID("pet-2"): ckError(.batchRequestFailed)
        ])

        let result = SyncErrorClassifier.classify(partial, accountAvailable: true)

        XCTAssertEqual(result.disposition, .transient)
        XCTAssertEqual(result.innermostCode, CKError.Code.serviceUnavailable.rawValue)
        XCTAssertFalse(result.isPermanent)
        XCTAssertEqual(result.userMessageKey, "cloudkit.error.partial")
    }

    func testOneUnexplainedErrorStopsTheRetryPromise() {
        let partial = partialFailure([
            recordID("client-1"): ckError(.networkFailure),
            recordID("client-2"): ckError(.internalError)
        ])

        let result = SyncErrorClassifier.classify(partial, accountAvailable: true)

        XCTAssertEqual(result.disposition, .unknown)
        XCTAssertEqual(result.innermostCode, CKError.Code.internalError.rawValue)
        XCTAssertNotEqual(result.userMessageKey, "cloudkit.error.partial")
    }

    func testOnlyCollateralErrorsStayUnknown() {
        let partial = partialFailure([
            recordID("client-1"): ckError(.batchRequestFailed),
            recordID("client-2"): ckError(.batchRequestFailed)
        ])

        let result = SyncErrorClassifier.classify(partial, accountAvailable: true)

        XCTAssertEqual(result.disposition, .unknown)
        XCTAssertEqual(result.innermostCode, CKError.Code.batchRequestFailed.rawValue)
        XCTAssertFalse(result.isPermanent)
    }

    func testServerRecordChangedIsBenignAndYieldsToRealFailures() {
        let conflictOnly = partialFailure([recordID("client-1"): ckError(.serverRecordChanged)])
        let conflictAndBusy = partialFailure([
            recordID("client-1"): ckError(.serverRecordChanged),
            recordID("client-2"): ckError(.zoneBusy)
        ])

        let benign = SyncErrorClassifier.classify(conflictOnly, accountAvailable: true)
        XCTAssertEqual(benign.disposition, .benign)
        XCTAssertFalse(benign.isPermanent)
        XCTAssertNil(benign.userMessageKey)

        XCTAssertEqual(SyncErrorClassifier.classify(conflictAndBusy, accountAvailable: true).disposition, .transient)
    }

    func testLimitExceededIsPermanent() {
        let partial = partialFailure([
            recordID("visit-1"): ckError(.limitExceeded),
            recordID("visit-2"): ckError(.batchRequestFailed)
        ])

        let result = SyncErrorClassifier.classify(partial, accountAvailable: true)

        XCTAssertEqual(result.disposition, .limitExceeded)
        XCTAssertTrue(result.isPermanent)
        XCTAssertEqual(result.userMessageKey, "cloudkit.error.limit_exceeded")
    }

    func testSchemaRejectionOutranksQuotaAndTransientSiblings() {
        let partial = partialFailure([
            recordID("client-1"): ckError(.quotaExceeded),
            recordID("client-2"): ckError(.networkFailure),
            recordID("loyalty-config"): ckError(.invalidArguments)
        ])

        XCTAssertEqual(SyncErrorClassifier.classify(partial, accountAvailable: true).disposition, .schemaRejected)
    }

    // MARK: - Quota

    func testQuotaNestedTwoLevelsDeepIsUserActionable() {
        let partial = partialFailure([
            recordID("visit-1"): ckError(.quotaExceeded),
            recordID("visit-2"): ckError(.batchRequestFailed)
        ])
        let viaUnderlying = NSError(domain: NSCocoaErrorDomain, code: 134417, userInfo: [NSUnderlyingErrorKey: partial])
        let viaDetailed = NSError(
            domain: NSCocoaErrorDomain,
            code: 134417,
            userInfo: [NSDetailedErrorsKey: [viaUnderlying]]
        )

        for error in [viaUnderlying, viaDetailed] {
            let result = SyncErrorClassifier.classify(error, accountAvailable: true)
            XCTAssertEqual(result.disposition, .userActionable(.quotaExceeded))
            XCTAssertEqual(result.innermostDomain, CKError.errorDomain)
            XCTAssertEqual(result.innermostCode, CKError.Code.quotaExceeded.rawValue)
            XCTAssertTrue(result.isPermanent)
            XCTAssertEqual(result.userMessageKey, "cloudkit.error.quota")
        }
    }

    // Same shapes as CloudKitSafetyRegressionTests' isQuotaExceededError cases,
    // so the monitor can delegate to the classifier without losing coverage.
    func testQuotaParityWithMonitorWrappedPartialFailure() {
        let partial = CKError(
            .partialFailure,
            userInfo: [
                CKPartialErrorsByItemIDKey: [
                    "record-1": CKError(.quotaExceeded)
                ]
            ]
        )
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134417, userInfo: [NSUnderlyingErrorKey: partial])

        XCTAssertEqual(
            SyncErrorClassifier.classify(wrapped, accountAvailable: true).disposition,
            .userActionable(.quotaExceeded)
        )
    }

    func testQuotaParityWithMonitorDaemonText() {
        let daemonStyleError = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.partialFailure.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Received error 47 (quotaExceeded) from the server"]
        )

        let result = SyncErrorClassifier.classify(daemonStyleError, accountAvailable: true)

        XCTAssertEqual(result.disposition, .userActionable(.quotaExceeded))
        XCTAssertEqual(result.innermostCode, CKError.Code.partialFailure.rawValue)
        XCTAssertEqual(result.serverMessage, "Received error 47 (quotaExceeded) from the server")
    }

    func testErrorCodeWinsOverQuotaText() {
        let error = NSError(
            domain: CKError.errorDomain,
            code: CKError.Code.networkFailure.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "quota exceeded"]
        )

        XCTAssertEqual(SyncErrorClassifier.classify(error, accountAvailable: true).disposition, .transient)
    }

    // MARK: - Account and setup

    func testSetup134400DependsOnAccountStatus() {
        let setupError = NSError(
            domain: NSCocoaErrorDomain,
            code: 134400,
            userInfo: [NSLocalizedDescriptionKey: "Unable to initialize without an iCloud account (CKAccountStatusNoAccount)."]
        )

        let signedIn = SyncErrorClassifier.classify(setupError, accountAvailable: true)
        XCTAssertEqual(signedIn.disposition, .setupFailedWhileSignedIn)
        XCTAssertEqual(signedIn.innermostDomain, NSCocoaErrorDomain)
        XCTAssertEqual(signedIn.innermostCode, 134400)
        XCTAssertNil(signedIn.serverMessage)
        XCTAssertTrue(signedIn.isPermanent)
        XCTAssertEqual(signedIn.userMessageKey, "cloudkit.error.setup_failed")

        let signedOut = SyncErrorClassifier.classify(setupError, accountAvailable: false)
        XCTAssertEqual(signedOut.disposition, .userActionable(.notAuthenticated))
        XCTAssertEqual(signedOut.userMessageKey, "cloudkit.error.signed_out")
    }

    func testNested134400IsDecidedByCode() {
        let setupError = NSError(domain: NSCocoaErrorDomain, code: 134400)
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134060, userInfo: [NSUnderlyingErrorKey: setupError])

        XCTAssertEqual(SyncErrorClassifier.classify(wrapped, accountAvailable: true).disposition, .setupFailedWhileSignedIn)
        XCTAssertEqual(
            SyncErrorClassifier.classify(wrapped, accountAvailable: false).disposition,
            .userActionable(.notAuthenticated)
        )
    }

    func testAccountErrorsAreUserActionable() {
        XCTAssertEqual(
            SyncErrorClassifier.classify(CKError(.notAuthenticated), accountAvailable: true).disposition,
            .userActionable(.notAuthenticated)
        )
        XCTAssertEqual(
            SyncErrorClassifier.classify(CKError(.accountTemporarilyUnavailable), accountAvailable: true).disposition,
            .userActionable(.accountTemporarilyUnavailable)
        )

        let deletedZone = SyncErrorClassifier.classify(CKError(.userDeletedZone), accountAvailable: true)
        XCTAssertEqual(deletedZone.disposition, .userActionable(.userDeletedZone))
        XCTAssertEqual(deletedZone.userMessageKey, "cloudkit.error.user_deleted_zone")
    }

    // MARK: - Network

    func testNetworkErrorsMapToTheConnectionMessage() {
        let offline = SyncErrorClassifier.classify(CKError(.networkUnavailable), accountAvailable: true)
        XCTAssertEqual(offline.disposition, .transient)
        XCTAssertEqual(offline.userMessageKey, "cloudkit.error.network")

        let urlError = NSError(domain: NSURLErrorDomain, code: URLError.Code.notConnectedToInternet.rawValue)
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: 134417, userInfo: [NSUnderlyingErrorKey: urlError])
        let viaURL = SyncErrorClassifier.classify(wrapped, accountAvailable: true)
        XCTAssertEqual(viaURL.disposition, .transient)
        XCTAssertEqual(viaURL.innermostDomain, NSURLErrorDomain)
        XCTAssertEqual(viaURL.userMessageKey, "cloudkit.error.network")
    }

    // MARK: - Fallbacks

    func testUnrecognisedErrorIsUnknownWithItsOwnCode() {
        let error = NSError(domain: "com.example.other", code: 42)

        let result = SyncErrorClassifier.classify(error, accountAvailable: true)

        XCTAssertEqual(result.disposition, .unknown)
        XCTAssertEqual(result.innermostDomain, "com.example.other")
        XCTAssertEqual(result.innermostCode, 42)
        XCTAssertEqual(result.diagnosticCode, "com.example.other.42")
        XCTAssertEqual(result.userMessageKey, "cloudkit.error.generic")
    }

    func testDeepNestingStopsAtTheDepthLimit() {
        var error: NSError = NSError(domain: CKError.errorDomain, code: CKError.Code.quotaExceeded.rawValue)
        for _ in 0..<20 {
            error = NSError(domain: NSCocoaErrorDomain, code: 134417, userInfo: [NSUnderlyingErrorKey: error])
        }

        let result = SyncErrorClassifier.classify(error, accountAvailable: true)

        XCTAssertEqual(result.disposition, .unknown)
        XCTAssertEqual(result.innermostCode, 134417)
    }

    func testPermanenceAndMessageKeyForEveryDisposition() {
        let expectations: [(SyncErrorClassifier.Disposition, Bool, String?)] = [
            (.transient, false, "cloudkit.error.partial"),
            (.userActionable(.quotaExceeded), true, "cloudkit.error.quota"),
            (.userActionable(.notAuthenticated), true, "cloudkit.error.signed_out"),
            (.userActionable(.accountTemporarilyUnavailable), true, "cloudkit.error.account_temporarily_unavailable"),
            (.userActionable(.userDeletedZone), true, "cloudkit.error.user_deleted_zone"),
            (.schemaRejected, true, "cloudkit.error.schema_rejected"),
            (.limitExceeded, true, "cloudkit.error.limit_exceeded"),
            (.benign, false, nil),
            (.setupFailedWhileSignedIn, true, "cloudkit.error.setup_failed"),
            (.unknown, false, "cloudkit.error.generic")
        ]

        for (disposition, isPermanent, messageKey) in expectations {
            let classification = SyncErrorClassifier.Classification(
                disposition: disposition,
                innermostDomain: CKError.errorDomain,
                innermostCode: CKError.Code.zoneBusy.rawValue,
                serverMessage: nil
            )
            XCTAssertEqual(classification.isPermanent, isPermanent, disposition.diagnosticName)
            XCTAssertEqual(classification.userMessageKey, messageKey, disposition.diagnosticName)
        }
    }

    // These strings are persisted and decoded elsewhere by raw value, so a
    // rename here would silently turn stored failures into "unknown".
    func testDiagnosticNamesAreStable() {
        let expected: [(SyncErrorClassifier.Disposition, String)] = [
            (.transient, "transient"),
            (.userActionable(.quotaExceeded), "userActionable.quotaExceeded"),
            (.userActionable(.notAuthenticated), "userActionable.notAuthenticated"),
            (.userActionable(.accountTemporarilyUnavailable), "userActionable.accountTemporarilyUnavailable"),
            (.userActionable(.userDeletedZone), "userActionable.userDeletedZone"),
            (.schemaRejected, "schemaRejected"),
            (.limitExceeded, "limitExceeded"),
            (.benign, "benign"),
            (.setupFailedWhileSignedIn, "setupFailedWhileSignedIn"),
            (.unknown, "unknown")
        ]

        for (disposition, name) in expected {
            XCTAssertEqual(disposition.diagnosticName, name)
        }
    }

    func testClassificationRoundTripsThroughJSON() throws {
        let original = SyncErrorClassifier.Classification(
            disposition: .userActionable(.quotaExceeded),
            innermostDomain: CKError.errorDomain,
            innermostCode: CKError.Code.quotaExceeded.rawValue,
            serverMessage: "Quota exceeded"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SyncErrorClassifier.Classification.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    // MARK: - Helpers

    private func recordID(_ name: String) -> CKRecord.ID {
        CKRecord.ID(
            recordName: name,
            zoneID: CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
        )
    }

    /// CloudKit puts the server's wording under "ServerErrorDescription" and
    /// repeats it in the localized description; both are set so the test
    /// matches either lookup.
    private func ckError(_ code: CKError.Code, serverMessage: String? = nil) -> CKError {
        guard let serverMessage else { return CKError(code) }
        return CKError(code, userInfo: [
            "ServerErrorDescription": serverMessage,
            NSLocalizedDescriptionKey: serverMessage
        ])
    }

    private func partialFailure(_ itemErrors: [CKRecord.ID: Error]) -> CKError {
        CKError(.partialFailure, userInfo: [
            CKPartialErrorsByItemIDKey: itemErrors,
            NSLocalizedDescriptionKey: "Failed to modify some records"
        ])
    }
}
