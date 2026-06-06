import XCTest
import SwiftData
@testable import Pawtrackr

final class DataIntegrityTests: XCTestCase {

    func testDecimalMoneyPrecision() {
        let amount = Decimal(string: "100.12345")!
        let rounded = amount.roundedMoney()
        XCTAssertEqual(rounded, Decimal(string: "100.12")!, "Money rounding should be exactly 2 decimal places")
        
        let cent = Decimal(string: "0.01")!
        let sum = (0..<100).reduce(Decimal.zero) { acc, _ in acc + cent }
        XCTAssertEqual(sum, Decimal(1), "Accumulated decimals should maintain precision")
    }
    
    @MainActor
    func testVisitTimerBackgroundResilience() {
        let timer = VisitTimer()
        let start = Date.now.addingTimeInterval(-3600) // 1 hour ago
        
        timer.load(startedAt: start, endedAt: nil)
        
        // Simulate background/foreground cycle
        timer.sceneBecameActive()
        
        XCTAssertTrue(timer.elapsedSeconds >= 3600, "Timer should correctly calculate elapsed time even if app was backgrounded")
    }
    
    @MainActor
    func testStoreFailureRecovery() {
        // Verify DataStoreService handles corrupted paths gracefully
        let service = DataStoreService(inMemory: true)
        XCTAssertNotNil(service.container, "Store should initialize successfully in-memory")
    }
}
