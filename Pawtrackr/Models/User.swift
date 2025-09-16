
import Foundation
import SwiftData

@Model
final class User {
    var uuid: UUID
    var name: String
    var email: String

    init(name: String, email: String) {
        self.uuid = UUID()
        self.name = name
        self.email = email
    }
}
