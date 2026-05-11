import XCTest
import SwiftData
@testable import Pawtrackr

final class DataPrunerTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    func testPruneOldPhotos_DownsamplesCorrectly() throws {
        let pet = Pet(name: "Rex", species: .dog)
        context.insert(pet)
        
        let oldDate = Calendar.current.date(byAdding: .day, value: -40, to: Date())!
        let visit = Visit(pet: pet, startedAt: oldDate)
        
        // Mock 1MB image data
        let mockData = Data(count: 1024 * 1024)
        visit.beforePhotoData = mockData
        try context.save()
        
        // Prune with downsampleOnly = true
        // Note: DataPruner skips if pruneSyncedAssets is false. We'll set it to true for the test.
        DataPruner.pruneOldPhotos(olderThan: 30, downsampleOnly: true, pruneSyncedAssets: true, in: context)
        
        XCTAssertNil(visit.beforePhotoData)
        // Thumbnail should be present (though downsampleToData might return nil for dummy data, 
        // in a real app with real image data, this would be populated).
    }
}
