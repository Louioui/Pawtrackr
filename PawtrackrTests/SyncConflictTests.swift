import XCTest
import SwiftData
@testable import Pawtrackr

@MainActor
final class SyncConflictTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    func testResolveVisitConflict_MergesNotesAndTags() async throws {
        let pet = Pet(name: "Buddy", species: .dog)
        context.insert(pet)
        let visit = Visit(pet: pet)
        visit.note = "Local note."
        visit.behaviorTags = ["Calm"]
        try context.save()
        
        let container = try XCTUnwrap(container)
        let actor = await Task.detached {
            SyncConflictActor(modelContainer: container)
        }.value
        
        let remoteData = SyncConflictActor.VisitData(
            note: "Remote edit.",
            behaviorTags: ["Anxious"]
        )
        
        try await actor.resolveVisitConflict(localID: visit.persistentModelID, remoteData: remoteData)
        
        // Refresh context
        let fetchedVisits = try context.fetch(FetchDescriptor<Visit>())
        let result = fetchedVisits.first!
        
        XCTAssertTrue(result.note?.contains("Local note") ?? false)
        XCTAssertTrue(result.note?.contains("Remote edit") ?? false)
        XCTAssertEqual(result.behaviorTags.count, 2)
        XCTAssertTrue(result.behaviorTags.contains("Anxious"))
        XCTAssertTrue(result.behaviorTags.contains("Calm"))
    }

    func testResolveVisitConflict_IsIdempotentAndSanitizesTags() async throws {
        let pet = Pet(name: "Buddy", species: .dog)
        context.insert(pet)
        let visit = Visit(pet: pet)
        visit.note = "Local note."
        visit.behaviorTags = ["Calm"]
        try context.save()

        let container = try XCTUnwrap(container)
        let actor = await Task.detached {
            SyncConflictActor(modelContainer: container)
        }.value
        let remoteData = SyncConflictActor.VisitData(
            note: "Remote edit.",
            behaviorTags: ["Anxious", " ", "Calm"]
        )

        try await actor.resolveVisitConflict(localID: visit.persistentModelID, remoteData: remoteData)
        try await actor.resolveVisitConflict(localID: visit.persistentModelID, remoteData: remoteData)

        let verificationContext = ModelContext(container)
        let result = try XCTUnwrap(try verificationContext.fetch(FetchDescriptor<Visit>()).first)
        let note = try XCTUnwrap(result.note)

        XCTAssertEqual(note.components(separatedBy: "[Remote Edit]:").count - 1, 1)
        XCTAssertEqual(result.behaviorTags, ["Anxious", "Calm"])
    }
}
