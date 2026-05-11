import Foundation
import Combine

@MainActor
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
           let v = try? JSONDecoder().decode([UserSession].self, from: d) {
            sessions = v
            // Restore tokens from Keychain
            for i in sessions.indices {
                sessions[i].accessToken = KeychainHelper.read(key: sessions[i].id.uuidString)
            }
        }
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
        let session: UserSession
        if let idx = sessions.firstIndex(where: { $0.displayName == displayName }) {
            sessions[idx].accessToken = accessToken
            saveSessions()
            session = sessions[idx]
        } else {
            let s = UserSession(displayName: displayName, accessToken: accessToken)
            sessions.append(s)
            saveSessions()
            session = s
        }
        if let token = accessToken, !token.isEmpty {
            KeychainHelper.save(key: session.id.uuidString, value: token)
        } else {
            KeychainHelper.delete(key: session.id.uuidString)
        }
        return session
    }

    func update(_ session: UserSession) {
        guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[idx] = session
        saveSessions()
        // Sync token to Keychain
        let key = session.id.uuidString
        if let token = session.accessToken, !token.isEmpty {
            KeychainHelper.save(key: key, value: token)
        } else {
            KeychainHelper.delete(key: key)
        }
    }

    func remove(sessionId: UUID) {
        sessions.removeAll { $0.id == sessionId }
        for i in courses.indices { courses[i].memberIds.removeAll { $0 == sessionId } }
        saveSessions()
        saveCourses()
        KeychainHelper.delete(key: sessionId.uuidString)
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

    /// Export format variants.
    enum ExportFormat {
        /// Full JSON with users, courses, and displayNames. Compatible with both iOS and Android.
        case fullJSON
        /// One cookie per line, no JSON wrapper. For sharing raw credentials without metadata.
        case rawCookies
    }

    func exportJSON(format: ExportFormat = .fullJSON, selectedIds: Set<UUID>? = nil) -> String {
        let ids = selectedIds ?? Set(sessions.map(\.id))
        let selected = sessions.filter { ids.contains($0.id) }

        switch format {
        case .fullJSON:
            let users = selected.map { s -> [String: Any] in
                ["displayName": s.displayName,
                 "accessToken": s.accessToken ?? ""]
            }
            let courseList = courses.compactMap { c -> [String: Any]? in
                let names = c.memberIds
                    .filter { ids.contains($0) }
                    .compactMap { id in sessions.first { $0.id == id }?.displayName }
                guard !names.isEmpty else { return nil }
                return ["name": c.name, "members": names]
            }
            var root: [String: Any] = ["users": users]
            if !courseList.isEmpty { root["courses"] = courseList }
            guard let data = try? JSONSerialization.data(withJSONObject: root, options: .prettyPrinted),
                  let str = String(data: data, encoding: .utf8) else { return "" }
            return str

        case .rawCookies:
            return selected.compactMap { s in
                guard let token = s.accessToken, !token.isEmpty else { return nil }
                return token
            }.joined(separator: "\n")
        }
    }

    enum ImportError: Error { case invalidFormat }

    /// Import from clipboard. Supports three formats:
    /// 1. JSON object: `{"users": [...], "courses": [...]}`  (iOS & Android export)
    /// 2. JSON array: `[{"displayName":"...","accessToken":"..."}]`
    /// 3. Raw cookie lines: one `_canvas_middle_session=...` per line
    @discardableResult
    func importJSON(_ text: String) throws -> (users: Int, courses: Int) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.invalidFormat }

        // Detect format by first non-whitespace character
        let first = trimmed[trimmed.startIndex]
        if first == "{" { return try importJSONObject(trimmed) }
        if first == "[" { return try importJSONArray(trimmed) }

        // Fallthrough: treat as raw cookie lines
        return try importRawCookies(trimmed)
    }

    // MARK: Private import helpers

    private func importJSONObject(_ json: String) throws -> (users: Int, courses: Int) {
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

    private func importJSONArray(_ json: String) throws -> (users: Int, courses: Int) {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { throw ImportError.invalidFormat }

        var imported = 0
        for obj in arr {
            let name = ((obj["displayName"] ?? obj["name"]) as? String ?? "").trimmingCharacters(in: .whitespaces)
            let token = ((obj["accessToken"] ?? obj["token"]) as? String ?? "").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            addOrUpdate(displayName: name, accessToken: token.isEmpty ? nil : token)
            imported += 1
        }
        return (imported, 0)
    }

    /// Import raw cookie lines. Each line is a standalone cookie string like
    /// `_canvas_middle_session=...`.  Since no displayName is provided, one is
    /// generated from a short hash of the cookie value.
    private func importRawCookies(_ text: String) throws -> (users: Int, courses: Int) {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.contains("=") }

        guard !lines.isEmpty else { throw ImportError.invalidFormat }

        var imported = 0
        for (i, cookie) in lines.enumerated() {
            let displayName = "User \(i + 1)"
            addOrUpdate(displayName: displayName, accessToken: cookie)
            imported += 1
        }
        return (imported, 0)
    }
}
