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

    // Persist the enum's String rawValue, NOT the enum itself. Storing a Codable
    // enum directly makes SwiftData create a "composite attribute" that FATALLY
    // crashes the *entire* fetch when a CloudKit-synced record can't be decoded
    // (e.g. after the case set changed — an older "Reminder" value broke macOS).
    // A plain String is migration- and CloudKit-safe, and any unknown/missing
    // value falls back to `.custom` instead of crashing.
    var typeRaw: String = MessageTemplate.TemplateType.custom.rawValue

    /// Non-persisted view over `typeRaw`, preserving the existing `template.type`
    /// API. `@Transient` is REQUIRED: without it the `@Model` macro still persists
    /// this as a composite `type` attribute, which is exactly what crashes when an
    /// old record holds an unknown raw value (e.g. "Reminder").
    @Transient
    var type: TemplateType {
        get { TemplateType(rawValue: typeRaw) ?? .custom }
        set { typeRaw = newValue.rawValue }
    }

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
        self.typeRaw = type.rawValue
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
            MessageTemplate(
                title: AppLocalization.localized("message_template.ready.title", value: "Ready for Pickup"),
                content: AppLocalization.localized("message_template.ready.content", value: "Hi [OwnerName], [PetName] is all finished and ready for pickup. See you soon!"),
                type: .readyForPickup
            ),
            MessageTemplate(
                title: AppLocalization.localized("message_template.reminder.title", value: "Appointment Reminder"),
                content: AppLocalization.localized("message_template.reminder.content", value: "Hi [OwnerName], this is a quick reminder for [PetName]'s Pawtrackr visit today. Reply if you need to adjust timing."),
                type: .appointmentReminder
            ),
            MessageTemplate(
                title: AppLocalization.localized("message_template.running_late.title", value: "Running Late"),
                content: AppLocalization.localized("message_template.running_late.content", value: "Hi [OwnerName], [PetName]'s visit is running a little longer than expected. We'll message you as soon as they're ready."),
                type: .runningLate
            ),
            MessageTemplate(
                title: AppLocalization.localized("message_template.follow_up.title", value: "Post-Visit Follow-up"),
                content: AppLocalization.localized("message_template.follow_up.content", value: "Hi [OwnerName], thanks for bringing [PetName] to Pawtrackr today! We hope they enjoyed their spa day."),
                type: .followUp
            )
        ]
    }
}
