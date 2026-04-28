import Testing
import Foundation
@testable import TongJiCanvas

@MainActor
@Suite(.serialized)
struct SessionRepositoryTests {

    let repo: SessionRepository

    init() {
        // Start with clean state
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "sessions_v2")
        defaults.removeObject(forKey: "courses_v2")
        defaults.removeObject(forKey: "selected_user_ids")
        KeychainHelper.deleteAll()
        repo = SessionRepository()
    }

    // MARK: - Session CRUD

    @Test func addSession() {
        let session = repo.addOrUpdate(displayName: "TestUser", accessToken: "test_token")
        #expect(session.displayName == "TestUser")
        #expect(session.accessToken == "test_token")
        #expect(session.hasCredentials)
        #expect(repo.sessions.count == 1)
    }

    @Test func addDuplicateSessionUpdatesExisting() {
        _ = repo.addOrUpdate(displayName: "TestUser", accessToken: "old_token")
        let updated = repo.addOrUpdate(displayName: "TestUser", accessToken: "new_token")
        #expect(repo.sessions.count == 1)
        #expect(updated.accessToken == "new_token")
    }

    @Test func removeSession() {
        let session = repo.addOrUpdate(displayName: "TestUser", accessToken: "token")
        #expect(repo.sessions.count == 1)
        repo.remove(sessionId: session.id)
        #expect(repo.sessions.isEmpty)
    }

    @Test func removeSessionCleansUpCourses() {
        let session = repo.addOrUpdate(displayName: "TestUser", accessToken: "token")
        var course = repo.addCourse(name: "TestCourse")
        course.memberIds = [session.id]
        repo.update(course)

        repo.remove(sessionId: session.id)
        let updated = repo.courses.first!
        #expect(updated.memberIds.isEmpty)
    }

    @Test func updateSession() {
        let session = repo.addOrUpdate(displayName: "TestUser", accessToken: "token")
        var updated = session
        updated.displayName = "Renamed"
        updated.accessToken = "new_token"
        repo.update(updated)
        #expect(repo.sessions.first?.displayName == "Renamed")
        #expect(repo.sessions.first?.accessToken == "new_token")
    }

    // MARK: - Token persistence in Keychain

    @Test func tokenSurvivesRepoReload() {
        _ = repo.addOrUpdate(displayName: "TestUser", accessToken: "secret_token")

        // Simulate app restart: create a new repo instance
        let newRepo = SessionRepository()
        #expect(newRepo.sessions.count == 1)
        #expect(newRepo.sessions.first?.accessToken == "secret_token")
    }

    @Test func nilTokenClearsKeychain() {
        _ = repo.addOrUpdate(displayName: "TestUser", accessToken: "secret_token")
        _ = repo.addOrUpdate(displayName: "TestUser", accessToken: nil)

        let newRepo = SessionRepository()
        #expect(newRepo.sessions.first?.accessToken == nil)
        #expect(!newRepo.sessions.first!.hasCredentials)
    }

    // MARK: - Courses

    @Test func addCourse() {
        let course = repo.addCourse(name: "Math")
        #expect(course.name == "Math")
        #expect(repo.courses.count == 1)
    }

    @Test func updateCourse() {
        let session = repo.addOrUpdate(displayName: "User", accessToken: "token")
        var course = repo.addCourse(name: "Math")
        course.memberIds = [session.id]
        repo.update(course)
        #expect(repo.courses.first?.memberIds.count == 1)
    }

    @Test func removeCourse() {
        let course = repo.addCourse(name: "Math")
        repo.remove(courseId: course.id)
        #expect(repo.courses.isEmpty)
    }

    // MARK: - Import / Export

    @Test func exportThenImportRoundtrip() throws {
        _ = repo.addOrUpdate(displayName: "Alice", accessToken: "alice_token")
        _ = repo.addOrUpdate(displayName: "Bob", accessToken: "bob_token")
        repo.addCourse(name: "Math")

        let json = repo.exportJSON()
        #expect(!json.isEmpty)
        #expect(json.contains("Alice"))
        #expect(json.contains("alice_token"))

        // Import into a fresh repo
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "sessions_v2")
        defaults.removeObject(forKey: "courses_v2")
        KeychainHelper.deleteAll()
        let newRepo = SessionRepository()

        let (users, courses) = try newRepo.importJSON(json)
        #expect(users == 2)
        #expect(courses == 1)
        #expect(newRepo.sessions.count == 2)
        #expect(newRepo.courses.count == 1)
        #expect(newRepo.sessions.first(where: { $0.displayName == "Alice" })?.accessToken == "alice_token")
    }

    @Test func importInvalidJSONThrows() {
        #expect(throws: SessionRepository.ImportError.self) {
            try repo.importJSON("not valid json {{{")
        }
    }

    // MARK: - Selected IDs

    @Test func selectedIdsDefaultsToAllSessions() {
        _ = repo.addOrUpdate(displayName: "Alice", accessToken: "a")
        _ = repo.addOrUpdate(displayName: "Bob", accessToken: "b")
        #expect(repo.selectedIds.count == 2)
    }

    @Test func selectedIdsPersists() {
        let alice = repo.addOrUpdate(displayName: "Alice", accessToken: "a")
        _ = repo.addOrUpdate(displayName: "Bob", accessToken: "b")
        repo.selectedIds = [alice.id]

        let newRepo = SessionRepository()
        #expect(newRepo.selectedIds.count == 1)
        #expect(newRepo.selectedIds.contains(alice.id))
    }
}
