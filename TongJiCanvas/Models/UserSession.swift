import Foundation

struct UserSession: Codable, Identifiable, Equatable {
    var id: UUID
    var displayName: String
    var accessToken: String?
    var lastVerifiedAt: Date?

    init(id: UUID = UUID(), displayName: String, accessToken: String? = nil, lastVerifiedAt: Date? = nil) {
        self.id = id
        self.displayName = displayName
        self.accessToken = accessToken
        self.lastVerifiedAt = lastVerifiedAt
    }

    var hasCredentials: Bool { !(accessToken?.isEmpty ?? true) }
}
