@testable import Eigin
import Foundation
import Testing

/// Pins down the partitioning ``AddAulaAccount`` relies on: the narrow
/// API-scoped cookie set persisted as ``AulaSession/cookies`` versus the full
/// broker/SSO jar persisted as ``AulaSession/brokerCookies``, and that the
/// latter survives a round trip back to `HTTPCookie` for seeding a silent
/// re-authorize.
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

    @Test func brokerCookiesKeepsTheFullJar() {
        let cookies = [
            cookie(name: "PHPSESSID", value: "api1", domain: "www.aula.dk"),
            cookie(name: "PHPSESSID", value: "login1", domain: "login.aula.dk"),
            cookie(name: "MOD_AUTH_CAS", value: "sso1", domain: "broker.unilogin.dk"),
        ]

        let brokerCookies = AulaSessionCookies.brokerCookies(from: cookies)

        #expect(brokerCookies.count == 3)
        #expect(brokerCookies
            .contains { $0.name == "MOD_AUTH_CAS" && $0.domain == "broker.unilogin.dk" })
    }

    @Test func httpCookiesRoundTripsNameValueDomainAndPath() {
        let original = [
            BrokerCookie(
                name: "MOD_AUTH_CAS",
                value: "sso1",
                domain: "broker.unilogin.dk",
                path: "/auth",
                isSecure: true,
                expiresDate: nil
            ),
        ]

        let reconstructed = AulaSessionCookies.httpCookies(from: original)

        #expect(reconstructed.count == 1)
        #expect(reconstructed.first?.name == "MOD_AUTH_CAS")
        #expect(reconstructed.first?.value == "sso1")
        #expect(reconstructed.first?.domain == "broker.unilogin.dk")
        #expect(reconstructed.first?.path == "/auth")
        #expect(reconstructed.first?.isSecure == true)
    }

    @Test func aulaSessionDecodesAnOlderBlobMissingTheBrokerFieldsAsNil() throws {
        // A session persisted before brokerCookies/userAgent/
        // guardianInstitutionProfileIDs existed — must decode cleanly with
        // all as nil, not crash or fail the whole blob.
        let json = Data("""
        {
            "cookies": {"Csrfp-Token": "csrf1"},
            "apiVersion": 24,
            "children": []
        }
        """.utf8)

        let session = try JSONDecoder().decode(AulaSession.self, from: json)

        #expect(session.brokerCookies == nil)
        #expect(session.userAgent == nil)
        #expect(session.guardianInstitutionProfileIDs == nil)
    }

    @Test func aulaChildDecodesAnOlderBlobMissingInstitutionProfileIDAsNil() throws {
        let json = Data("""
        {"id": "1", "name": "Astrid", "institution": "Solsikken"}
        """.utf8)

        let child = try JSONDecoder().decode(AulaChild.self, from: json)

        #expect(child.institutionProfileID == nil)
    }
}
