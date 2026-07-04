import XCTest
import SwiftUI
@testable import Pawtrackr

final class DashboardPerformanceTests: XCTestCase {
    private weak var weakDashboardViewModel: DashboardViewModel?

    @MainActor
    func testDashboardTimeToInteractive() async throws {
        let dataStore = DataStoreService(inMemory: true)
        let eventBus = GlobalEventBus()
        
        let start = CFAbsoluteTimeGetCurrent()
        
        let vm = DashboardViewModel(dataStore: dataStore, eventBus: eventBus)
        
        // In a real test, we'd observe the state change.
        // For PoC, we await the refresh.
        await vm.refresh()
        
        let end = CFAbsoluteTimeGetCurrent()
        let duration = (end - start) * 1000
        
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
