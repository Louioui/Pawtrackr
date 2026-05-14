import XCTest
import SwiftData
@testable import Pawtrackr

@MainActor
final class RecallSchedulingActorTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema(PawtrackrSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    func testScheduleRecall_CreatesAppointmentOffMainContext() async throws {
        let pet = Pet(name: "Buddy", species: .dog)
        context.insert(pet)
        try context.save()

        let scheduledDate = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: .now))
        let container = try XCTUnwrap(container)
        let actor = await Task.detached {
            RecallSchedulingActor(modelContainer: container)
        }.value

        let result = try await actor.scheduleRecall(forPetID: pet.uuid, date: scheduledDate)

        let verificationContext = ModelContext(container)
        let appointments = try verificationContext.fetch(FetchDescriptor<Appointment>())
        let appointment = try XCTUnwrap(appointments.first)

        XCTAssertEqual(result.petName, "Buddy")
        XCTAssertEqual(appointments.count, 1)
        XCTAssertEqual(appointment.pet?.uuid, pet.uuid)
        XCTAssertEqual(appointment.date.timeIntervalSince1970, scheduledDate.timeIntervalSince1970, accuracy: 0.001)
    }
}
