import Testing
import Foundation
@testable import TongJiCanvas

struct UserSessionTests {

    @Test func defaultInitGeneratesUUID() {
        let s1 = UserSession(displayName: "Alice")
        let s2 = UserSession(displayName: "Alice")
        #expect(s1.id != s2.id)
    }

    @Test func hasCredentialsFalseWhenNil() {
        let s = UserSession(displayName: "Alice", accessToken: nil)
        #expect(!s.hasCredentials)
    }

    @Test func hasCredentialsFalseWhenEmpty() {
        let s = UserSession(displayName: "Alice", accessToken: "")
        #expect(!s.hasCredentials)
    }

    @Test func hasCredentialsTrueWhenPresent() {
        let s = UserSession(displayName: "Alice", accessToken: "some_token")
        #expect(s.hasCredentials)
    }

    @Test func codableRoundTripOmitsAccessToken() throws {
        let original = UserSession(displayName: "Alice", accessToken: "secret")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UserSession.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.displayName == original.displayName)
        // accessToken is excluded from CodingKeys — must not survive round-trip
        #expect(decoded.accessToken == nil)
    }

    @Test func equatableByValue() {
        let id = UUID()
        let a = UserSession(id: id, displayName: "Alice", accessToken: "t1")
        let b = UserSession(id: id, displayName: "Alice", accessToken: "t2")
        // Equatable uses synthesized implementation (all stored properties)
        // accessToken differs, so they are not equal
        #expect(a != b)
    }
}
