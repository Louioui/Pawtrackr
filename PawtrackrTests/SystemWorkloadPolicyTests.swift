import Foundation
import XCTest
@testable import Pawtrackr

final class SystemWorkloadPolicyTests: XCTestCase {
    func testHeavyBackgroundWorkAllowsNominalAndFairThermalStates() {
        XCTAssertNil(
            SystemWorkloadPolicy.heavyBackgroundWorkDeferralReason(
                thermalState: .nominal,
                isLowPowerModeEnabled: false
            )
        )
        XCTAssertNil(
            SystemWorkloadPolicy.heavyBackgroundWorkDeferralReason(
                thermalState: .fair,
                isLowPowerModeEnabled: false
            )
        )
    }

    func testHeavyBackgroundWorkDefersForSeriousAndCriticalThermalStates() {
        XCTAssertEqual(
            SystemWorkloadPolicy.heavyBackgroundWorkDeferralReason(
                thermalState: .serious,
                isLowPowerModeEnabled: false
            ),
            "thermal_state_serious"
        )
        XCTAssertEqual(
            SystemWorkloadPolicy.heavyBackgroundWorkDeferralReason(
                thermalState: .critical,
                isLowPowerModeEnabled: false
            ),
            "thermal_state_critical"
        )
    }

    func testHeavyBackgroundWorkDefersForLowPowerMode() {
        XCTAssertEqual(
            SystemWorkloadPolicy.heavyBackgroundWorkDeferralReason(
                thermalState: .nominal,
                isLowPowerModeEnabled: true
            ),
            "low_power_mode"
        )
    }

    func testScheduledMaintenanceUsesWorkloadPolicyBeforeHeavyWork() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let scheduledTasks = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Pawtrackr/Core/Services/ScheduledTasks.swift"),
            encoding: .utf8
        )

        let policyRange = try XCTUnwrap(scheduledTasks.range(of: "SystemWorkloadPolicy.heavyBackgroundWorkDeferralReason()"))
        let summaryRange = try XCTUnwrap(scheduledTasks.range(of: "SummaryUpdater.rebuildAllSummaries"))
        XCTAssertLessThan(
            policyRange.lowerBound,
            summaryRange.lowerBound,
            "Scheduled maintenance must check thermal/low-power policy before summary rebuild and photo pruning."
        )
    }
}
