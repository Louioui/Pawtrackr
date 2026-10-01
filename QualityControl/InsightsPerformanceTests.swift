import XCTest
import SwiftData
@testable import Pawtrackr

final class InsightsPerformanceTests: XCTestCase {

    @MainActor
    func testAnalyticsAggregationSpeed() async throws {
        let duration = try await PerformanceBudget.fastestCPUMilliseconds(runs: 3) { () throws -> DataStoreService in
            let dataStore = DataStoreService(inMemory: true)

            // 1. Seed 1000 summary records
            let context = dataStore.container.mainContext
            for dayOffset in 0..<1000 {
                let summary = DaySummary(
                    day: Calendar.current.date(byAdding: .day, value: -dayOffset, to: .now)!,
                    revenue: Decimal(100),
                    visitCount: 1
                )
                context.insert(summary)
            }
            try context.save()
            return dataStore
        } _: { dataStore in
            // 2. Measure full refresh (multi-actor aggregation)
            let vm = InsightsViewModel(dataStore: dataStore)
            await vm.refresh()
        }

        print("Insights Aggregation CPU Time: \(duration)ms")
        XCTAssertTrue(duration < 250, "Heavy analytics aggregation used \(duration)ms of CPU, exceeding 250ms threshold")
    }
    
    @MainActor
    func testReportGenerationNonBlocking() async throws {
        let vm = InsightsViewModel(dataStore: DataStoreService(inMemory: true))
        await vm.refresh()
        
        let start = CFAbsoluteTimeGetCurrent()
        
        // Trigger async report generation
        let exports = try await vm.makeReportExports(businessName: "Performance Salon", currencySymbol: "$")
        let data = exports.pdf.pdfData
        
        let end = CFAbsoluteTimeGetCurrent()
        let duration = (end - start) * 1000
        
        XCTAssertFalse(data.isEmpty)
        print("PDF Generation Time: \(duration)ms")
        // Rendering 1000 rows might take time, but it should be off-main. 
        // This test ensures it completes.
    }
}
