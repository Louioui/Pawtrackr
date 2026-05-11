import Foundation
import SwiftData

@Model
final class AppFeedback {
    var uuid: UUID = UUID()
    var date: Date = Date()
    var type: String = "Bug" // Bug, Feature, Feedback
    var content: String = ""
    var appVersion: String = ""
    var isSubmitted: Bool = false

    init(type: String, content: String) {
        self.uuid = UUID()
        self.date = Date()
        self.type = type
        self.content = content
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        self.isSubmitted = false
    }
}
