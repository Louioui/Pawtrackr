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
    // Defaults for CloudKit compatibility.
    var title: String = ""
    var content: String = ""
    var type: TemplateType = MessageTemplate.TemplateType.custom
    
    enum TemplateType: String, Codable, CaseIterable, Identifiable {
        case readyForPickup = "Ready"
        case appointmentReminder = "Appointment Reminder"
        case runningLate = "Running Late"
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
            let total = visit.total > .zero ? visit.total : visit.effectiveTotal
            result = result.replacingOccurrences(of: "[Total]", with: total.moneyString)
        }
        return result
    }
    
    static var defaults: [MessageTemplate] {
        [
            MessageTemplate(title: "Ready for Pickup", content: "Hi [OwnerName], [PetName] is all finished and ready for pickup. See you soon!", type: .readyForPickup),
            MessageTemplate(title: "Appointment Reminder", content: "Hi [OwnerName], this is a quick reminder for [PetName]'s Pawtrackr visit today. Reply if you need to adjust timing.", type: .appointmentReminder),
            MessageTemplate(title: "Running Late", content: "Hi [OwnerName], [PetName]'s visit is running a little longer than expected. We'll message you as soon as they're ready.", type: .runningLate),
            MessageTemplate(title: "Post-Visit Follow-up", content: "Hi [OwnerName], thanks for bringing [PetName] to Pawtrackr today! We hope they enjoyed their spa day.", type: .followUp)
        ]
    }
}
