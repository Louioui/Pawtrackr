//
//  RecallSchedulingActor.swift
//  Pawtrackr
//
//  Background SwiftData actor for recall appointment creation.
//

import Foundation
import SwiftData

@ModelActor
final actor RecallSchedulingActor {
    struct ScheduledRecall: Sendable {
        let petName: String
        let date: Date
    }

    enum SchedulingError: LocalizedError {
        case petNotFound

        var errorDescription: String? {
            switch self {
            case .petNotFound:
                return "The pet for this recall could not be found."
            }
        }
    }

    func scheduleRecall(forPetID petID: UUID, date: Date) async throws -> ScheduledRecall {
        let descriptor = FetchDescriptor<Pet>(
            predicate: #Predicate<Pet> { pet in
                pet.uuid == petID
            }
        )

        guard let pet = try modelContext.fetch(descriptor).first else {
            throw SchedulingError.petNotFound
        }

        let appointment = Appointment(date: date, pet: pet, user: nil)
        modelContext.insert(appointment)
        try modelContext.save()

        return ScheduledRecall(petName: pet.name, date: appointment.date)
    }
}
