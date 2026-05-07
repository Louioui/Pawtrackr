
import Foundation
import SwiftData

@Model
final class Appointment {
    enum Status: String, Codable {
        case scheduled
        case checkedIn
        case cancelled
    }

    // Defaults + optional pet for CloudKit compatibility.
    // CloudKit requires every to-one relationship to be optional, so `pet`
    // is now `Pet?`. Callers must use optional chaining (`appointment.pet?.name`).
    var uuid: UUID = UUID()
    var date: Date = Date()
    var pet: Pet?
    var status: Status = Appointment.Status.scheduled
    var user: User?
    var visit: Visit?

    init(date: Date, pet: Pet, user: User?, status: Status = .scheduled) {
        self.uuid = UUID()
        self.date = date
        self.pet = pet
        self.user = user
        self.status = status
    }
}
