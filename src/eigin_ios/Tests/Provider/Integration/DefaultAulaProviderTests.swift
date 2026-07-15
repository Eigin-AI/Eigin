@testable import Eigin
import Foundation
import Testing

/// Pins down how the provider shapes Aula's API responses into the agent-facing
/// contract, and that a version bump gets persisted so it survives the next
/// launch.
@Suite("DefaultAulaProvider")
struct DefaultAulaProviderTests {
    private let integrationID = UUID()

    private func baseSession(version: Int = 21) -> AulaSession {
        AulaSession(
            accessToken: "tok",
            refreshToken: nil,
            expiresAt: nil,
            cookies: ["Csrfp-Token": "csrf1"],
            apiVersion: version,
            children: [AulaChild(id: "1", name: "Astrid", institution: "Solsikken")]
        )
    }

    private func makeProvider(
        store: FakeAulaCredentialStore,
        http: FakeAulaHTTP,
        refresher: any AulaTokenRefresher = FakeAulaTokenRefresher.returning(accessToken: "unused"),
        reauthorizer: any AulaReauthorizer =
            FakeAulaReauthorizer(result: .failure(FakeAulaReauthorizer.ReauthorizeUnavailable()))
    ) -> DefaultAulaProvider {
        DefaultAulaProvider(
            integrationID: integrationID,
            credentialStore: store,
            apiClient: AulaAPIClient(http: http),
            tokenRefresher: refresher,
            reauthorizer: reauthorizer
        )
    }

    private func session(
        accessToken: String = "tok",
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        brokerCookies: [BrokerCookie]? = nil
    ) -> AulaSession {
        AulaSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            cookies: ["Csrfp-Token": "csrf1"],
            apiVersion: 24,
            children: [AulaChild(id: "1", name: "Astrid", institution: "Solsikken")],
            brokerCookies: brokerCookies
        )
    }

    /// A minimal broker cookie, standing in for the captured SSO jar.
    private func brokerCookie() -> BrokerCookie {
        BrokerCookie(
            name: "MOD_AUTH_CAS",
            value: "sso1",
            domain: "broker.unilogin.dk",
            path: "/",
            isSecure: true,
            expiresDate: nil
        )
    }

    @Test func childrenComeFromTheStoredSessionWithoutANetworkCall() async throws {
        let store = FakeAulaCredentialStore(seed: [integrationID: baseSession()])
        let http = FakeAulaHTTP { _ in (500, Data()) }
        let provider = makeProvider(store: store, http: http)

        let children = try await provider.children()

        #expect(children == [AulaChild(id: "1", name: "Astrid", institution: "Solsikken")])
        #expect(http.requests.isEmpty)
    }

    @Test func listMessagesMapsThreadsAndStripsHTML() async throws {
        let store = FakeAulaCredentialStore(seed: [integrationID: baseSession()])
        let threads = Data("""
        {
          "data": {
            "threads": [
              {
                "id": 10,
                "subject": "Weekly letter",
                "read": false,
                "latestMessage": {
                  "text": {"html": "<p>Hello <b>parents</b></p>"},
                  "sender": {"fullName": "Teacher"},
                  "sendDateTime": "2026-07-13T10:00:00"
                }
              }
            ]
          }
        }
        """.utf8)
        let http = FakeAulaHTTP { _ in (200, threads) }
        let provider = makeProvider(store: store, http: http)

        let messages = try await provider.listMessages(limit: 20)

        #expect(messages.count == 1)
        let message = try #require(messages.first)
        #expect(message.threadID == "10")
        #expect(message.subject == "Weekly letter")
        #expect(message.latestSender == "Teacher")
        #expect(message.preview == "Hello parents")
        #expect(message.unread == true)
    }

    @Test func updatesDegradesWhenOneSourceFails() async throws {
        let store = FakeAulaCredentialStore(seed: [integrationID: baseSession()])
        // Messages fail; the rest return empty-but-valid payloads.
        let http = FakeAulaHTTP { request in
            switch request.aulaMethod {
            case "messaging.getThreads":
                (500, Data())
            case "notifications.getNotificationsForActiveProfile":
                (200, Data(#"{"data":[]}"#.utf8))
            case "posts.getAllPosts":
                (200, Data(#"{"data":{"posts":[]}}"#.utf8))
            case "calendar.getEventsByProfileIdsAndResourceIds":
                (200, Data(#"{"data":[]}"#.utf8))
            default:
                (200, Data("{}".utf8))
            }
        }
        let provider = makeProvider(store: store, http: http)

        let digest = try await provider.updates(days: 7)

        #expect(digest.recentMessages.isEmpty)
        #expect(digest.unreadMessageCount == 0)
        #expect(digest.notifications.isEmpty)
    }

    @Test func updatesThrowsWhenEverySourceFails() async throws {
        let store = FakeAulaCredentialStore(seed: [integrationID: baseSession()])
        // Every endpoint 401s, as if the session had fully expired — a partial
        // degrade here would hide that the account needs reconnecting.
        let http = FakeAulaHTTP { _ in (401, Data()) }
        let provider = makeProvider(store: store, http: http)

        await #expect(throws: AulaProviderError.sessionExpired) {
            _ = try await provider.updates(days: 7)
        }
    }

    @Test func calendarPostsMethodAndProfileIdsAsJsonBody() async throws {
        let store = FakeAulaCredentialStore(seed: [integrationID: baseSession()])
        let http = FakeAulaHTTP { _ in (200, Data(#"{"data":[]}"#.utf8)) }
        let provider = makeProvider(store: store, http: http)

        _ = try await provider.calendar(from: "2026-07-13", to: "2026-07-13")

        let request = try #require(http.requests.first)
        // POST with the method in the query and the args in a JSON body — the
        // GET form is rejected with a 400.
        #expect(request.httpMethod == "POST")
        #expect(request.aulaMethod == "calendar.getEventsByProfileIdsAndResourceIds")
        let body = try #require(request.httpBody)
        let json = try #require(
            try JSONSerialization.jsonObject(with: body) as? [String: Any]
        )
        #expect(json["instProfileIds"] as? [Int] == [1])
        #expect(json["resourceIds"] as? [Int] == [])
        // Date-only input is widened to Aula's full-timestamp form.
        let start = try #require(json["start"] as? String)
        #expect(start.hasPrefix("2026-07-13 00:00:00"))
    }

    @Test func calendarCapsAnOverlongWindowToTheSupportedSpan() async throws {
        let store = FakeAulaCredentialStore(seed: [integrationID: baseSession()])
        let http = FakeAulaHTTP { _ in (200, Data(#"{"data":[]}"#.utf8)) }
        let provider = makeProvider(store: store, http: http)

        // Two-month window — Aula 403s past ~a month, so the end is capped.
        _ = try await provider.calendar(from: "2026-06-01", to: "2026-08-01")

        let body = try #require(http.requests.first?.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let end = try #require(json["end"] as? String)
        // from + 21 days, advanced to next midnight for an inclusive day.
        #expect(end.hasPrefix("2026-06-23 00:00:00"))
    }

    @Test func updatesDropsNotificationsWithNoText() async throws {
        let store = FakeAulaCredentialStore(seed: [integrationID: baseSession()])
        let http = FakeAulaHTTP { request in
            switch request.aulaMethod {
            case "notifications.getNotificationsForActiveProfile":
                (
                    200,
                    Data(
                        #"{"data":[{"message":"Real one","triggered":"2026-07-14"},{"triggered":"2026-07-14"},{"message":""}]}"#
                            .utf8
                    )
                )
            default:
                (200, Data("{}".utf8))
            }
        }
        let provider = makeProvider(store: store, http: http)

        let digest = try await provider.updates(days: 7)

        #expect(digest.notifications.count == 1)
        #expect(digest.notifications.first?.text == "Real one")
    }

    @Test func postsAreScopedByChildAndGuardianInstitutionProfileIDs() async throws {
        // Without `institutionProfileIds[]`, Aula falls back to a narrow
        // default feed that misses group/room-wide and institution-wide
        // posts — this pins down that both ID sources are sent.
        let scoped = AulaSession(
            accessToken: "tok",
            refreshToken: nil,
            expiresAt: nil,
            cookies: ["Csrfp-Token": "csrf1"],
            apiVersion: 24,
            children: [
                AulaChild(
                    id: "1",
                    name: "Astrid",
                    institution: "Solsikken",
                    institutionProfileID: 101
                ),
                AulaChild(
                    id: "2",
                    name: "Emil",
                    institution: "Nørre Skole",
                    institutionProfileID: 102
                ),
            ],
            guardianInstitutionProfileIDs: [201]
        )
        let store = FakeAulaCredentialStore(seed: [integrationID: scoped])
        let http = FakeAulaHTTP { _ in (200, Data(#"{"data":{"posts":[]}}"#.utf8)) }
        let provider = makeProvider(store: store, http: http)

        _ = try await provider.updates(days: 7)

        let request = try #require(http.requests.first { $0.aulaMethod == "posts.getAllPosts" })
        let ids = try URLComponents(url: #require(request.url), resolvingAgainstBaseURL: false)?
            .queryItems?.filter { $0.name == "institutionProfileIds[]" }.compactMap(\.value)
        #expect(Set(ids ?? []) == ["101", "102", "201"])
    }

    @Test func postsOmitInstitutionProfileIdsWhenNoneAreCaptured() async throws {
        // A session connected before institution-profile IDs were captured
        // falls back to the old request shape rather than sending an empty
        // (and likely worse-scoped) array.
        let store = FakeAulaCredentialStore(seed: [integrationID: baseSession()])
        let http = FakeAulaHTTP { _ in (200, Data(#"{"data":{"posts":[]}}"#.utf8)) }
        let provider = makeProvider(store: store, http: http)

        _ = try await provider.updates(days: 7)

        let request = try #require(http.requests.first { $0.aulaMethod == "posts.getAllPosts" })
        let hasInstitutionProfileIds = try URLComponents(
            url: #require(request.url),
            resolvingAgainstBaseURL: false
        )?.queryItems?.contains { $0.name == "institutionProfileIds[]" } ?? false
        #expect(hasInstitutionProfileIds == false)
    }

    @Test func refreshesAnExpiredTokenBeforeCallingAndPersistsIt() async throws {
        let expired = session(refreshToken: "refresh", expiresAt: Date.now.addingTimeInterval(-10))
        let store = FakeAulaCredentialStore(seed: [integrationID: expired])
        let refresher = FakeAulaTokenRefresher.returning(accessToken: "fresh-tok")
        let http = FakeAulaHTTP { _ in (200, Data(#"{"data":{"threads":[]}}"#.utf8)) }
        let provider = makeProvider(store: store, http: http, refresher: refresher)

        _ = try await provider.listMessages(limit: 10)

        #expect(refresher.refreshCount == 1)
        // The call went out on the refreshed token, and the new session is saved.
        let sentToken = try #require(http.requests.first?.url?.absoluteString)
        #expect(sentToken.contains("access_token=fresh-tok"))
        #expect(store.read(for: integrationID)?.accessToken == "fresh-tok")
    }

    @Test func doesNotRefreshWhenTheTokenIsStillValid() async throws {
        // Token unexpired → no proactive refresh; a successful call goes out on
        // the stored token untouched.
        let valid = session(refreshToken: "refresh", expiresAt: Date.now.addingTimeInterval(3600))
        let store = FakeAulaCredentialStore(seed: [integrationID: valid])
        let refresher = FakeAulaTokenRefresher.returning(accessToken: "fresh-tok")
        let http = FakeAulaHTTP { _ in (200, Data(#"{"data":{"threads":[]}}"#.utf8)) }
        let provider = makeProvider(store: store, http: http, refresher: refresher)

        _ = try await provider.listMessages(limit: 10)

        #expect(refresher.refreshCount == 0)
        #expect(try #require(http.requests.first?.url?.absoluteString).contains("access_token=tok"))
    }

    @Test func doesNotRefreshAForbiddenWhileTheTokenIsStillValid() async throws {
        // A 403 with a valid (unexpired) token is never a base-token problem —
        // a fresh access token (same scope) wouldn't change it — so the
        // proactive refresh path is never triggered by it. With no broker
        // cookies persisted on this session there's nothing to silently
        // re-authorize with either, so it surfaces as `sessionExpired` outright.
        let valid = session(refreshToken: "refresh", expiresAt: Date.now.addingTimeInterval(3600))
        let store = FakeAulaCredentialStore(seed: [integrationID: valid])
        let refresher = FakeAulaTokenRefresher.returning(accessToken: "fresh-tok")
        let http = FakeAulaHTTP { _ in (403, Data()) }
        let provider = makeProvider(store: store, http: http, refresher: refresher)

        await #expect(throws: AulaProviderError.sessionExpired) {
            _ = try await provider.listMessages(limit: 10)
        }
        #expect(refresher.refreshCount == 0)
    }

    @Test func silentlyReauthorizesOnSessionExpiredThenRetries() async throws {
        // The MitID step-up assurance / web session lapses independently of
        // the access token and isn't restored by a `refresh_token` grant. A
        // session with a persisted broker jar recovers by silently re-walking
        // the authorize chain instead of surfacing straight to reconnect.
        let valid = session(
            refreshToken: "refresh",
            expiresAt: Date.now.addingTimeInterval(3600),
            brokerCookies: [brokerCookie()]
        )
        let store = FakeAulaCredentialStore(seed: [integrationID: valid])
        let reauthorizer = FakeAulaReauthorizer.returning(accessToken: "fresh-tok")
        let http = FakeAulaHTTP { request in
            request.url!.absoluteString.contains("access_token=tok")
                ? (401, Data())
                : (200, Data(#"{"data":{"threads":[]}}"#.utf8))
        }
        let provider = makeProvider(store: store, http: http, reauthorizer: reauthorizer)

        _ = try await provider.listMessages(limit: 10)

        #expect(reauthorizer.reauthorizeCount == 1)
        #expect(http.requests.count == 2)
        let sentToken = try #require(http.requests.last?.url?.absoluteString)
        #expect(sentToken.contains("access_token=fresh-tok"))
        #expect(store.read(for: integrationID)?.accessToken == "fresh-tok")
        #expect(store.read(for: integrationID)?.brokerCookies?.isEmpty == false)
    }

    @Test func surfacesSessionExpiredWhenReauthorizeItselfFails() async throws {
        let valid = session(
            refreshToken: "refresh",
            expiresAt: Date.now.addingTimeInterval(3600),
            brokerCookies: [brokerCookie()]
        )
        let store = FakeAulaCredentialStore(seed: [integrationID: valid])
        let reauthorizer =
            FakeAulaReauthorizer(result: .failure(FakeAulaReauthorizer.ReauthorizeUnavailable()))
        let http = FakeAulaHTTP { _ in (401, Data()) }
        let provider = makeProvider(store: store, http: http, reauthorizer: reauthorizer)

        await #expect(throws: AulaProviderError.sessionExpired) {
            _ = try await provider.listMessages(limit: 10)
        }
        #expect(reauthorizer.reauthorizeCount == 1)
    }

    @Test func doesNotLoopWhenTheRetryAfterReauthorizeStillFails() async throws {
        // A successful re-authorize followed by another 401 means the retry
        // itself is a genuine, unrelated failure — not looped forever.
        let valid = session(
            refreshToken: "refresh",
            expiresAt: Date.now.addingTimeInterval(3600),
            brokerCookies: [brokerCookie()]
        )
        let store = FakeAulaCredentialStore(seed: [integrationID: valid])
        let reauthorizer = FakeAulaReauthorizer.returning(accessToken: "fresh-tok")
        let http = FakeAulaHTTP { _ in (401, Data()) }
        let provider = makeProvider(store: store, http: http, reauthorizer: reauthorizer)

        await #expect(throws: AulaProviderError.sessionExpired) {
            _ = try await provider.listMessages(limit: 10)
        }
        #expect(reauthorizer.reauthorizeCount == 1)
        #expect(http.requests.count == 2)
    }

    @Test func surfacesSessionExpiredWhenTheRefreshItselfFails() async throws {
        let expired = session(refreshToken: "refresh", expiresAt: Date.now.addingTimeInterval(-10))
        let store = FakeAulaCredentialStore(seed: [integrationID: expired])
        let refresher =
            FakeAulaTokenRefresher(result: .failure(FakeAulaTokenRefresher.RefreshUnavailable()))
        let http = FakeAulaHTTP { _ in (200, Data(#"{"data":{"threads":[]}}"#.utf8)) }
        let provider = makeProvider(store: store, http: http, refresher: refresher)

        await #expect(throws: AulaProviderError.sessionExpired) {
            _ = try await provider.listMessages(limit: 10)
        }
    }

    @Test func persistsTheApiVersionAfterA410Bump() async throws {
        let store = FakeAulaCredentialStore(seed: [integrationID: baseSession(version: 21)])
        let threads = Data(#"{"data":{"threads":[]}}"#.utf8)
        let http = FakeAulaHTTP { request in
            request.url!.absoluteString.contains("/v21/") ? (410, Data()) : (200, threads)
        }
        let provider = makeProvider(store: store, http: http)

        _ = try await provider.listMessages(limit: 20)

        #expect(store.read(for: integrationID)?.apiVersion == 22)
    }
}
