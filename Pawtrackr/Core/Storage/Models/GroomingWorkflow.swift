import Foundation
import SwiftData

@Model
final class GroomingWorkflow {
    @Attribute(.unique) var workflowToken: String // Format: "YYYY-MM-DD_PetID"
    
    var id: UUID
    var petName: String
    
    // Timer Anchor: We sync the *start date*, not the running clock seconds
    var timerStartedAt: Date?
    var isWorkflowActive: Bool
    
    // Split Checkout Flow parameters to prevent write collisions
    var checkoutCompletedAt: Date?
    var paymentMethod: String
    var receptionistNotes: String
    var groomerNotes: String
    
    init(petID: UUID, petName: String) {
        self.id = UUID()
        self.workflowToken = "\(Date().formatted(date: .numeric, time: .omitted))_\(petID.uuidString)"
        self.petName = petName
        self.isWorkflowActive = false
        self.paymentMethod = "None"
        self.receptionistNotes = ""
        self.groomerNotes = ""
    }
}
