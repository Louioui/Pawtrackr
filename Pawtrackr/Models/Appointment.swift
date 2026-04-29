
import Foundation
import SwiftData

@Model
final class Appointment {
    enum Status: String, Codable {
        case scheduled
        case checkedIn
        case cancelled
    }

    var uuid: UUID
    var date: Date
    var pet: Pet
    var status: Status = Appointment.Status.scheduled
    @Relationship(deleteRule: .nullify) var user: User?
    @Relationship(deleteRule: .nullify) var visit: Visit?

    init(date: Date, pet: Pet, user: User?, status: Status = .scheduled) {
        self.uuid = UUID()
        self.date = date
        self.pet = pet
        self.user = user
        self.status = status
    }
}
