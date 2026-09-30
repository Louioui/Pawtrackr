
import Foundation
import SwiftData

@Model
final class User {
    var uuid: UUID = UUID()
    var name: String = ""
    var email: String = ""

    @Relationship(deleteRule: .nullify, inverse: \Client.user) var clients: [Client]? = []
    @Relationship(deleteRule: .nullify, inverse: \Pet.user) var pets: [Pet]? = []
    @Relationship(deleteRule: .nullify, inverse: \Visit.user) var visits: [Visit]? = []

    init(name: String, email: String) {
        self.uuid = UUID()
        self.name = name
        self.email = email
    }
}
