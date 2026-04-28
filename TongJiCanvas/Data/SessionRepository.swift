import Foundation
import Combine

final class SessionRepository: ObservableObject {
    @Published private(set) var sessions: [UserSession] = []
    @Published private(set) var courses: [Course] = []

    private let defaults = UserDefaults.standard
    private let sessionsKey = "sessions_v2"
    private let coursesKey  = "courses_v2"
    private let selectedKey = "selected_user_ids"

    init() { load() }

    // MARK: - Load / Save

    private func load() {
        if let d = defaults.data(forKey: sessionsKey),
           let v = try? JSONDecoder().decode([UserSession].self, from: d) { sessions = v }
        if let d = defaults.data(forKey: coursesKey),
           let v = try? JSONDecoder().decode([Course].self, from: d)  { courses = v }
    }

    private func saveSessions() {
        if let d = try? JSONEncoder().encode(sessions) { defaults.set(d, forKey: sessionsKey) }
    }

    private func saveCourses() {
        if let d = try? JSONEncoder().encode(courses) { defaults.set(d, forKey: coursesKey) }
    }

    // MARK: - Sessions

    @discardableResult
    func addOrUpdate(displayName: String, accessToken: String?) -> UserSession {
        if let idx = sessions.firstIndex(where: { $0.displayName == displayName }) {
            sessions[idx].accessToken = accessToken
            sessions[idx].lastVerifiedAt = Date()
            saveSessions()
            return sessions[idx]
        }
        let s = UserSession(displayName: displayName, accessToken: accessToken, lastVerifiedAt: Date())
        sessions.append(s)
        saveSessions()
        return s
    }

    func update(_ session: UserSession) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[idx] = session
        saveSessions()
    }

    func remove(sessionId: UUID) {
        sessions.removeAll { $0.id == sessionId }
        for i in courses.indices { courses[i].memberIds.removeAll { $0 == sessionId } }
        saveSessions()
        saveCourses()
    }

    // MARK: - Courses

    @discardableResult
    func addCourse(name: String) -> Course {
        let c = Course(name: name)
        courses.append(c)
        saveCourses()
        return c
    }

    func update(_ course: Course) {
        guard let idx = courses.firstIndex(where: { $0.id == course.id }) else { return }
        courses[idx] = course
        saveCourses()
    }

    func remove(courseId: UUID) {
        courses.removeAll { $0.id == courseId }
        saveCourses()
    }

    // MARK: - Selected IDs

    var selectedIds: Set<UUID> {
        get {
            guard let d = defaults.data(forKey: selectedKey),
                  let ids = try? JSONDecoder().decode([UUID].self, from: d)
            else { return Set(sessions.map(\.id)) }
            return Set(ids).intersection(Set(sessions.map(\.id)))
        }
        set {
            if let d = try? JSONEncoder().encode(Array(newValue)) { defaults.set(d, forKey: selectedKey) }
        }
    }

    // MARK: - Import / Export

    func exportJSON() -> String {
        let users = sessions.map { ["displayName": $0.displayName, "accessToken": $0.accessToken ?? ""] as [String: Any] }
        let courseList = courses.map { c -> [String: Any] in
            let names = c.memberIds.compactMap { id in sessions.first { $0.id == id }?.displayName }
            return ["name": c.name, "members": names]
        }
        var root: [String: Any] = ["users": users]
        if !courseList.isEmpty { root["courses"] = courseList }
        guard let data = try? JSONSerialization.data(withJSONObject: root, options: .prettyPrinted),
              let str = String(data: data, encoding: .utf8) else { return "" }
        return str
    }

    enum ImportError: Error { case invalidFormat }

    @discardableResult
    func importJSON(_ json: String) throws -> (users: Int, courses: Int) {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ImportError.invalidFormat }

        var nameToId: [String: UUID] = [:]
        sessions.forEach { nameToId[$0.displayName] = $0.id }
        var importedUsers = 0, importedCourses = 0

        if let arr = root["users"] as? [[String: Any]] {
            for obj in arr {
                let name = ((obj["displayName"] ?? obj["name"]) as? String ?? "").trimmingCharacters(in: .whitespaces)
                let token = ((obj["accessToken"] ?? obj["token"]) as? String ?? "").trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                let s = addOrUpdate(displayName: name, accessToken: token.isEmpty ? nil : token)
                nameToId[name] = s.id
                importedUsers += 1
            }
        }

        if let arr = root["courses"] as? [[String: Any]] {
            for obj in arr {
                guard let cname = obj["name"] as? String, !cname.isEmpty else { continue }
                let memberNames = obj["members"] as? [String] ?? []
                let memberIds = memberNames.compactMap { nameToId[$0] }
                if let existing = courses.first(where: { $0.name == cname }) {
                    var updated = existing
                    updated.memberIds = Array(Set(updated.memberIds + memberIds))
                    update(updated)
                } else {
                    var c = addCourse(name: cname)
                    c.memberIds = memberIds
                    update(c)
                }
                importedCourses += 1
            }
        }
        return (importedUsers, importedCourses)
    }
}
