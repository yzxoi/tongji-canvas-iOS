import Foundation
import WebKit

enum CookieHelper {
    static let canvasDomain = "canvas.tongji.edu.cn"

    /// Parse a "name=value; name2=value2" string into HTTPCookie objects for the Canvas domain.
    static func parseCookies(from string: String, domain: String = canvasDomain) -> [HTTPCookie] {
        string.components(separatedBy: "; ")
            .compactMap { part -> HTTPCookie? in
                let pair = part.trimmingCharacters(in: .whitespaces)
                guard let eqRange = pair.range(of: "=") else { return nil }
                let name  = String(pair[pair.startIndex..<eqRange.lowerBound]).trimmingCharacters(in: .whitespaces)
                let value = String(pair[eqRange.upperBound...])
                guard !name.isEmpty else { return nil }
                return HTTPCookie(properties: [
                    .name:   name,
                    .value:  value,
                    .domain: domain,
                    .path:   "/",
                    .secure: "TRUE"
                ])
            }
    }

    /// Inject cookies into a WKWebsiteDataStore asynchronously.
    @MainActor
    static func inject(cookies: [HTTPCookie], into store: WKWebsiteDataStore) async {
        await withTaskGroup(of: Void.self) { group in
            for cookie in cookies {
                group.addTask { @MainActor in
                    await store.httpCookieStore.setCookie(cookie)
                }
            }
        }
    }

    /// Collect all cookies for the Canvas domain from a data store.
    @MainActor
    static func captureCanvasCookies(from store: WKHTTPCookieStore) async -> String {
        let all = await store.allCookies()
        return all
            .filter { $0.domain.contains(canvasDomain) || $0.domain.contains("tongji.edu.cn") }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }
}
