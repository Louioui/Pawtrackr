
import Foundation
import SwiftData

@Model
final class Appointment {
    var uuid: UUID
    var date: Date
    var pet: Pet
    @Relationship(deleteRule: .nullify) var user: User?

    init(date: Date, pet: Pet, user: User?) {
        self.uuid = UUID()
        self.date = date
        self.pet = pet
        self.user = user
    }
}
