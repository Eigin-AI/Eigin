@testable import Eigin
import Foundation
import Testing

/// Pins down the narrowing ``AddAulaAccount`` relies on: the API-scoped cookie
/// set persisted as ``AulaSession/cookies`` keeps only the non-`login.`
/// `aula.dk` host cookies the API client sends on every call.
@Suite("AulaSessionCookies")
struct AulaSessionCookiesTests {
    private func cookie(name: String, value: String, domain: String) -> HTTPCookie {
        HTTPCookie(properties: [
            .name: name,
            .value: value,
            .domain: domain,
            .path: "/",
        ])!
    }

    @Test func apiCookiesKeepsOnlyNonLoginAulaHost() {
        let cookies = [
            cookie(name: "PHPSESSID", value: "api1", domain: "www.aula.dk"),
            cookie(name: "PHPSESSID", value: "login1", domain: "login.aula.dk"),
            cookie(name: "MOD_AUTH_CAS", value: "sso1", domain: "broker.unilogin.dk"),
        ]

        let apiCookies = AulaSessionCookies.apiCookies(from: cookies)

        #expect(apiCookies == ["PHPSESSID": "api1"])
    }

    @Test func aulaSessionDecodesAnOlderBlobMissingOptionalFieldsAsNil() throws {
        // A session persisted before guardianInstitutionProfileIDs existed —
        // and one persisted with now-removed brokerCookies/userAgent keys —
        // must decode cleanly, ignoring leftover keys, not crash or fail the
        // whole blob.
        let json = Data("""
        {
            "cookies": {"Csrfp-Token": "csrf1"},
            "apiVersion": 24,
            "children": [],
            "userAgent": "legacy-agent",
            "brokerCookies": []
        }
        """.utf8)

        let session = try JSONDecoder().decode(AulaSession.self, from: json)

        #expect(session.guardianInstitutionProfileIDs == nil)
        #expect(session.cookies == ["Csrfp-Token": "csrf1"])
    }

    @Test func aulaChildDecodesAnOlderBlobMissingInstitutionProfileIDAsNil() throws {
        let json = Data("""
        {"id": "1", "name": "Astrid", "institution": "Solsikken"}
        """.utf8)

        let child = try JSONDecoder().decode(AulaChild.self, from: json)

        #expect(child.institutionProfileID == nil)
    }
}
