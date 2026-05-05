//
//  MessageTemplate.swift
//  Pawtrackr
//
//  Model for reusable communication templates.
//

import Foundation
import SwiftData

@Model
final class MessageTemplate {
    var title: String
    var content: String
    var type: TemplateType
    
    enum TemplateType: String, Codable, CaseIterable, Identifiable {
        case appointmentReminder = "Reminder"
        case readyForPickup = "Ready"
        case followUp = "Follow-up"
        case custom = "Custom"
        
        var id: String { rawValue }
    }
    
    init(title: String, content: String, type: TemplateType = .custom) {
        self.title = title
        self.content = content
        self.type = type
    }
    
    @MainActor
    func processedContent(pet: Pet?, visit: Visit?) -> String {
        var result = content
        if let pet = pet {
            result = result.replacingOccurrences(of: "[PetName]", with: pet.name)
        }
        if let owner = pet?.owner {
            result = result.replacingOccurrences(of: "[OwnerName]", with: owner.firstName)
        }
        if let visit = visit {
            result = result.replacingOccurrences(of: "[Time]", with: visit.startedAt.formatted(date: .omitted, time: .shortened))
            result = result.replacingOccurrences(of: "[Total]", with: visit.totalCurrencyString)
        }
        return result
    }
    
    static var defaults: [MessageTemplate] {
        [
            MessageTemplate(title: "Ready for Pickup", content: "Hi [OwnerName], [PetName] is all finished and ready for pickup! See you soon.", type: .readyForPickup),
            MessageTemplate(title: "Appointment Reminder", content: "Reminder: [PetName] has a grooming appointment today at [Time]. See you then!", type: .appointmentReminder),
            MessageTemplate(title: "Post-Visit Follow-up", content: "Hi [OwnerName], thanks for bringing [PetName] to Pawtrackr today! We hope they enjoyed their spa day.", type: .followUp)
        ]
    }
}
