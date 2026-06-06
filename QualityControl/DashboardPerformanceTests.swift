import XCTest
import SwiftUI
@testable import Pawtrackr

final class DashboardPerformanceTests: XCTestCase {

    @MainActor
    func testDashboardTimeToInteractive() async throws {
        let dataStore = DataStoreService(inMemory: true)
        let eventBus = GlobalEventBus()
        
        let start = CFAbsoluteTimeGetCurrent()
        
        let vm = DashboardViewModel(dataStore: dataStore, eventBus: eventBus)
        
        // Measure time to reach .loaded state
        let expectation = XCTestExpectation(description: "Dashboard should load within 150ms")
        
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
        weak var weakVM = vm
        
        vm = nil
        
        XCTAssertNil(weakVM, "DashboardViewModel has a retain cycle")
    }
}
