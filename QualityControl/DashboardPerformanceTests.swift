import XCTest
import SwiftUI
@testable import Pawtrackr

final class DashboardPerformanceTests: XCTestCase {
    private weak var weakDashboardViewModel: DashboardViewModel?

    @MainActor
    func testDashboardTimeToInteractive() async throws {
        let duration = await PerformanceBudget.fastestMilliseconds {
            DataStoreService(inMemory: true)
        } _: { dataStore in
            let vm = DashboardViewModel(dataStore: dataStore, eventBus: GlobalEventBus())
            await vm.refresh()
        }

        print("Dashboard Time to Interactive: \(duration)ms")

        XCTAssertTrue(duration < 150, "Dashboard took \(duration)ms to become interactive, exceeding 150ms threshold")
    }
    
    @MainActor
    func testRetainCycleSafety() {
        var vm: DashboardViewModel? = DashboardViewModel(dataStore: DataStoreService(inMemory: true), eventBus: GlobalEventBus())
        weakDashboardViewModel = vm
        
        vm = nil
        
        XCTAssertNil(weakDashboardViewModel, "DashboardViewModel has a retain cycle")
    }
}
