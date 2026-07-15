@testable import Eigin
import Foundation
import Testing

/// The connection verifier is the gate on saving an Aula integration, so these
/// pin down what "verified" means: the profiles call succeeds, its children are
/// captured, any version bump carries through, and failures map to the right
/// user-facing error.
@Suite("AulaConnectionVerifier")
struct AulaConnectionVerifierTests {
    private let session = AulaSession(
        accessToken: "tok",
        refreshToken: nil,
        expiresAt: nil,
        cookies: ["Csrfp-Token": "csrf1"],
        apiVersion: 21,
        children: []
    )

    private let profilesJSON = Data("""
    {
      "data": {
        "profiles": [
          {
            "children": [
              {"id": 1, "name": "Astrid", "institutionProfile": {"id": 101, "institutionName": "Solsikken"}},
              {"id": 2, "name": "Emil", "institutionProfile": {"id": 102, "institutionName": "Nørre Skole"}}
            ],
            "institutionProfiles": [
              {"id": 201, "institutionName": "Solsikken"},
              {"id": 202, "institutionName": "Nørre Skole"}
            ]
          }
        ]
      }
    }
    """.utf8)

    @Test func capturesChildrenOnSuccess() async throws {
        let http = FakeAulaHTTP { _ in (200, profilesJSON) }
        let client = AulaAPIClient(http: http)

        let verified = try await AulaConnectionVerifier.verify(session: session, apiClient: client)

        #expect(verified.children.count == 2)
        #expect(verified.children[0] == AulaChild(
            id: "1",
            name: "Astrid",
            institution: "Solsikken",
            institutionProfileID: 101
        ))
        #expect(verified.children[1] == AulaChild(
            id: "2",
            name: "Emil",
            institution: "Nørre Skole",
            institutionProfileID: 102
        ))
        #expect(http.requests.first?.aulaMethod == "profiles.getProfilesByLogin")
    }

    @Test func capturesTheGuardiansOwnInstitutionProfileIDs() async throws {
        let http = FakeAulaHTTP { _ in (200, profilesJSON) }
        let client = AulaAPIClient(http: http)

        let verified = try await AulaConnectionVerifier.verify(session: session, apiClient: client)

        #expect(verified.guardianInstitutionProfileIDs == [201, 202])
    }

    @Test func carriesThroughAVersionBump() async throws {
        let http = FakeAulaHTTP { request in
            request.url!.absoluteString.contains("/v21/")
                ? (410, Data())
                : (200, profilesJSON)
        }
        let client = AulaAPIClient(http: http)

        let verified = try await AulaConnectionVerifier.verify(session: session, apiClient: client)

        #expect(verified.apiVersion == 22)
        #expect(verified.children.count == 2)
    }

    @Test func mapsRejectedSessionToSessionRejected() async throws {
        let http = FakeAulaHTTP { _ in (401, Data()) }
        let client = AulaAPIClient(http: http)

        await #expect(throws: AulaConnectionError.sessionRejected) {
            _ = try await AulaConnectionVerifier.verify(session: session, apiClient: client)
        }
    }

    @Test func mapsUnreadableResponseToUnexpectedResponse() async throws {
        let http = FakeAulaHTTP { _ in (200, Data("not json".utf8)) }
        let client = AulaAPIClient(http: http)

        await #expect(throws: AulaConnectionError.unexpectedResponse) {
            _ = try await AulaConnectionVerifier.verify(session: session, apiClient: client)
        }
    }
}
