import XCTest
@testable import Pawtrackr

final class VisitTimerTests: XCTestCase {
    
    @MainActor
    func testTimer_StartAndStop_CalculatesElapsed() {
        let timer = VisitTimer()
        let start = Date()
        let end = start.addingTimeInterval(120) // 2 minutes
        
        timer.start(at: start)
        XCTAssertTrue(timer.isRunning)
        
        timer.stop(at: end)
        XCTAssertFalse(timer.isRunning)
        XCTAssertEqual(timer.elapsedSeconds, 120)
        XCTAssertEqual(timer.formattedElapsed, "2 m 0 s")
    }
    
    @MainActor
    func testTimer_PauseAndResume_AccumulatesSeconds() {
        let timer = VisitTimer()
        let start1 = Date()
        let pause1 = start1.addingTimeInterval(30)
        
        timer.start(at: start1)
        timer.pause(at: pause1)
        XCTAssertEqual(timer.elapsedSeconds, 30)
        
        let resume1 = pause1.addingTimeInterval(60) // Resuming 1 minute later
        let stop1 = resume1.addingTimeInterval(30)
        
        timer.start(at: resume1)
        timer.stop(at: stop1)
        
        XCTAssertEqual(timer.elapsedSeconds, 60) // 30s + 30s
    }
    
    @MainActor
    func testTimer_LoadFromVisit_InitializesCorrectly() {
        let timer = VisitTimer()
        let start = Date().addingTimeInterval(-3600) // Started 1 hour ago
        
        timer.load(startedAt: start, endedAt: nil)
        
        XCTAssertTrue(timer.isRunning)
        XCTAssertGreaterThanOrEqual(timer.elapsedSeconds, 3600)
    }
}
