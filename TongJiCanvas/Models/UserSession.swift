import Foundation

struct UserSession: Codable, Identifiable, Equatable {
    var id: UUID
    var displayName: String
    /// Stored in Keychain, excluded from UserDefaults persistence.
    var accessToken: String?

    enum CodingKeys: String, CodingKey {
        case id, displayName
    }

    init(id: UUID = UUID(), displayName: String, accessToken: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.accessToken = accessToken
    }

    var hasCredentials: Bool { !(accessToken?.isEmpty ?? true) }
}
