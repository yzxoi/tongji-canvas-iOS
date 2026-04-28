import Foundation

struct Course: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var memberIds: [UUID]

    init(id: UUID = UUID(), name: String, memberIds: [UUID] = []) {
        self.id = id
        self.name = name
        self.memberIds = memberIds
    }
}
