import Testing
@testable import TongJiCanvas

struct CookieHelperTests {

    @Test func parseSingleCookie() {
        let cookies = CookieHelper.parseCookies(from: "session=abc123")
        #expect(cookies.count == 1)
        #expect(cookies.first?.name == "session")
        #expect(cookies.first?.value == "abc123")
    }

    @Test func parseMultipleCookies() {
        let cookies = CookieHelper.parseCookies(from: "a=1; b=2; c=3")
        #expect(cookies.count == 3)
        let names = cookies.map(\.name)
        #expect(names.contains("a"))
        #expect(names.contains("b"))
        #expect(names.contains("c"))
    }

    @Test func parseEmptyStringReturnsEmpty() {
        let cookies = CookieHelper.parseCookies(from: "")
        #expect(cookies.isEmpty)
    }

    @Test func parseCookieWithEqualsInValue() {
        // Base64 values contain '='
        let cookies = CookieHelper.parseCookies(from: "token=abc==; other=val")
        #expect(cookies.count == 2)
        let token = cookies.first(where: { $0.name == "token" })
        #expect(token?.value == "abc==")
    }

    @Test func parseEmptyNameSkipped() {
        let cookies = CookieHelper.parseCookies(from: "=value; valid=ok")
        #expect(cookies.count == 1)
        #expect(cookies.first?.name == "valid")
    }

    @Test func parseCookieWithEmptyValue() {
        let cookies = CookieHelper.parseCookies(from: "key=")
        #expect(cookies.count == 1)
        #expect(cookies.first?.name == "key")
        #expect(cookies.first?.value == "")
    }

    @Test func cookiesUsesCanvasDomainByDefault() {
        let cookies = CookieHelper.parseCookies(from: "k=v")
        #expect(cookies.first?.domain == CookieHelper.canvasDomain)
    }

    @Test func cookiesUsesCustomDomain() {
        let cookies = CookieHelper.parseCookies(from: "k=v", domain: "example.com")
        #expect(cookies.first?.domain == "example.com")
    }

    @Test func realWorldCanvasCookieString() {
        let raw = "_canvas_k5_login=1; _legacy_normandy_session=xyz; _canvas_ses=abc123"
        let cookies = CookieHelper.parseCookies(from: raw)
        #expect(cookies.count == 3)
    }
}
