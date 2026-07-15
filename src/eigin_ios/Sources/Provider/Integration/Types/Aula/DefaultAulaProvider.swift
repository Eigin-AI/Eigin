import Foundation

/// Live ``AulaProvider`` backend, talking to Aula's unofficial JSON API via
/// ``AulaAPIClient`` (which owns the tested cookie/csrf/version-bump plumbing).
///
/// The per-endpoint response decoding is a best-effort mapping from the shapes
/// the community clients observe; it is expected to be refined against the live
/// API (see the integration doc), which is why decoding is deliberately lenient
/// and a failed sub-fetch degrades the digest rather than failing the whole call.
final class DefaultAulaProvider: AulaProvider, @unchecked Sendable {
    private let integrationID: UUID
    private let credentialStore: any AulaCredentialStore
    private let apiClient: AulaAPIClient
    private let tokenRefresher: any AulaTokenRefresher
    private let reauthorizer: any AulaReauthorizer

    init(
        integrationID: UUID,
        credentialStore: any AulaCredentialStore,
        apiClient: AulaAPIClient,
        tokenRefresher: any AulaTokenRefresher = DefaultAulaTokenRefresher(),
        reauthorizer: any AulaReauthorizer = DefaultAulaReauthorizer()
    ) {
        self.integrationID = integrationID
        self.credentialStore = credentialStore
        self.apiClient = apiClient
        self.tokenRefresher = tokenRefresher
        self.reauthorizer = reauthorizer
    }

    // MARK: - AulaProvider

    func children() async throws -> [AulaChild] {
        // Captured at connect time (see AulaConnectionVerifier) and kept in the
        // session, so the agent always has family context without a round trip.
        try session().children
    }

    /// Builds the combined digest from best-effort sub-fetches. Each source
    /// degrades independently on failure (a hiccup in, say, calendar shouldn't
    /// blank out messages) — but if *every* source fails, that's not a partial
    /// degrade, it's the account needing attention (most commonly an expired
    /// session past the refresh token's own lifetime); surface that error
    /// instead of a healthy-looking empty digest that would hide the need to
    /// reconnect.
    func updates(days: Int) async throws -> AulaUpdatesDigest {
        let now = Date.now
        let end = Calendar.current.date(byAdding: .day, value: max(days, 1), to: now) ?? now

        let messages = await Self.attempt { try await self.listMessages(limit: 10) }
        let notifications = await Self.attempt { try await self.fetchNotifications() }
        let posts = await Self.attempt { try await self.fetchPosts() }
        let events = await Self.attempt {
            try await self.calendar(from: Self.isoDate(now), to: Self.isoDate(end))
        }

        if messages.value == nil, notifications.value == nil, posts.value == nil,
           events.value == nil
        {
            throw messages.error ?? notifications.error ?? posts.error ?? events.error
                ?? AulaProviderError.requestFailed("All Aula sources failed")
        }

        return AulaUpdatesDigest(
            unreadMessageCount: (messages.value ?? []).filter(\.unread).count,
            recentMessages: messages.value ?? [],
            notifications: notifications.value ?? [],
            upcomingEvents: events.value ?? [],
            recentPosts: posts.value ?? []
        )
    }

    /// Runs a sub-fetch, capturing its error instead of throwing so a caller
    /// can degrade individual sources independently while still noticing when
    /// every source failed for the same reason (see ``updates(days:)``).
    private static func attempt<T>(
        _ work: () async throws -> T
    ) async -> (value: T?, error: Error?) {
        do {
            return try await (work(), nil)
        } catch {
            return (nil, error)
        }
    }

    func listMessages(limit: Int) async throws -> [AulaMessageSummary] {
        let data = try await get(
            method: "messaging.getThreads",
            queryItems: [
                .init(name: "sortOn", value: "date"),
                .init(name: "orderDirection", value: "desc"),
                .init(name: "page", value: "0"),
            ]
        )
        let decoded = try decode(AulaThreadsResponse.self, from: data)
        return decoded.data.threads.prefix(limit).map { thread in
            AulaMessageSummary(
                threadID: String(thread.id),
                subject: thread.subject ?? "(no subject)",
                latestSender: thread.latestMessage?.sender?.fullName ?? "Unknown",
                preview: thread.latestMessage?.text?.plainText ?? "",
                unread: !(thread.read ?? true),
                date: thread.latestMessage?.sendDateTime ?? ""
            )
        }
    }

    func readMessage(threadID: String) async throws -> AulaMessageThread {
        let data = try await get(
            method: "messaging.getMessagesForThread",
            queryItems: [
                .init(name: "threadId", value: threadID),
                .init(name: "page", value: "0"),
            ]
        )
        let decoded = try decode(AulaThreadMessagesResponse.self, from: data)
        let entries = decoded.data.messages.map { message in
            AulaMessageEntry(
                sender: message.sender?.fullName ?? "Unknown",
                text: message.text?.plainText ?? "",
                date: message.sendDateTime ?? ""
            )
        }
        return AulaMessageThread(
            threadID: threadID,
            subject: decoded.data.subject ?? "(no subject)",
            messages: entries
        )
    }

    func calendar(from: String, to: String) async throws -> [AulaCalendarEvent] {
        // This method takes a JSON POST body, not query params — the GET form
        // is rejected with a 400. `instProfileIds` are the children's profile
        // ids; `resourceIds` is required but may be empty. Aula rejects windows
        // wider than roughly a month with a 403, so the upper bound is capped.
        let profileIDs = try session().children.compactMap { Int($0.id) }
        let cappedTo = Self.cappingSpan(from: from, to: to)
        let data = try await post(
            method: "calendar.getEventsByProfileIdsAndResourceIds",
            jsonBody: [
                "instProfileIds": profileIDs,
                "resourceIds": [Int](),
                "start": Self.aulaDateTime(from, endOfDay: false),
                "end": Self.aulaDateTime(cappedTo, endOfDay: true),
            ]
        )
        let decoded = try decode(AulaCalendarResponse.self, from: data)
        return decoded.data.map { event in
            AulaCalendarEvent(
                id: String(event.id),
                title: event.title ?? "(untitled)",
                start: event.startDateTime ?? "",
                end: event.endDateTime ?? "",
                childName: event.belongsToProfiles?.first.map(String.init),
                location: event.primaryResourceText
            )
        }
    }

    // MARK: - Endpoints used only by the digest

    private func fetchNotifications() async throws -> [AulaNotification] {
        let data = try await get(method: "notifications.getNotificationsForActiveProfile")
        let decoded = try decode(AulaNotificationsResponse.self, from: data)
        // Many Aula notifications carry only a type/reference and no message
        // text (e.g. a presence or album event); those surface as blank lines
        // that just pollute the digest, so drop anything with no text.
        return decoded.data.compactMap { notification in
            let text = notification.message ?? ""
            guard !text.isEmpty else { return nil }
            return AulaNotification(text: text, date: notification.triggered ?? "")
        }
    }

    private func fetchPosts() async throws -> [AulaPost] {
        // Aula scopes the feed via `institutionProfileIds[]` — without it,
        // it falls back to a narrow default that misses group/room-wide and
        // institution-wide posts (only some child- or profile-specific ones
        // come through). Combine each child's institution-profile id with
        // the guardian's own; both are captured at connect time (see
        // ``AulaConnectionVerifier``). Absent on a session connected before
        // this existed — falls back to the old, narrower request shape until
        // the next reconnect.
        let current = try session()
        let institutionProfileIDs = current.children.compactMap(\.institutionProfileID)
            + (current.guardianInstitutionProfileIDs ?? [])
        var queryItems = [
            URLQueryItem(name: "parent", value: "profile"),
            URLQueryItem(name: "index", value: "0"),
            URLQueryItem(name: "limit", value: "20"),
        ]
        queryItems += institutionProfileIDs.map {
            URLQueryItem(name: "institutionProfileIds[]", value: String($0))
        }
        let data = try await get(method: "posts.getAllPosts", queryItems: queryItems)
        let decoded = try decode(AulaPostsResponse.self, from: data)
        return decoded.data.posts.map {
            AulaPost(
                id: String($0.id),
                title: $0.title ?? "",
                content: $0.content?.plainText ?? "",
                author: $0.ownerProfile?.fullName ?? "",
                date: $0.timestamp ?? ""
            )
        }
    }

    // MARK: - Request plumbing

    /// Runs a GET method through ``AulaAPIClient`` with refresh-and-retry.
    private func get(method: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        try await withRefresh { session in
            try await self.apiClient.get(method: method, queryItems: queryItems, session: session)
        }
    }

    /// Runs a POST method (JSON body) through ``AulaAPIClient`` with
    /// refresh-and-retry.
    private func post(method: String, jsonBody: [String: Any]) async throws -> Data {
        try await withRefresh { session in
            try await self.apiClient.post(method: method, jsonBody: jsonBody, session: session)
        }
    }

    /// Makes an API call against the stored session, transparently refreshing an
    /// expired access token first so callers never hit the ~1h re-login. We
    /// refresh proactively off the stored `expiresAt` rather than reactively off
    /// a `403`, because a `403` while the token is still valid is *usually* a
    /// genuine forbidden (e.g. calendar range) — a fresh access token (same
    /// scope) wouldn't change that, so refreshing there would just waste a
    /// round trip.
    ///
    /// A `sessionExpired` that reaches here despite a valid access token means
    /// something the base-token refresh can't fix: the MitID step-up assurance
    /// or the web session (`PHPSESSID`) has lapsed — both decay independently
    /// of the access token and aren't restored by a `refresh_token` grant. For
    /// that we fall back once to a silent re-authorize (``reauthorizedSession``)
    /// and retry; a second failure means the broker/SSO session itself is gone
    /// and there's nothing left to recover without an interactive reconnect.
    private func withRefresh(
        _ call: (AulaSession) async throws -> AulaResponse
    ) async throws -> Data {
        var current = try session()
        if tokenExpired(current), current.refreshToken != nil {
            current = try await refreshedSession(current)
        }
        do {
            return try await persisting(call(current), against: current)
        } catch AulaProviderError.sessionExpired {
            guard let recovered = try await reauthorizedSession(current) else {
                throw AulaProviderError.sessionExpired
            }
            return try await persisting(call(recovered), against: recovered)
        }
    }

    /// Whether the access token is at or past its expiry (with a small buffer to
    /// refresh just before it lapses). A nil expiry is treated as valid — Aula
    /// reliably returns `expires_in`, so an absent one means we simply don't
    /// know, and we'd rather act on a real `sessionExpired` than refresh blindly.
    private func tokenExpired(_ session: AulaSession) -> Bool {
        guard let expiresAt = session.expiresAt else { return false }
        return expiresAt <= Date.now.addingTimeInterval(60)
    }

    /// Exchanges the refresh token for a fresh access token, persists the
    /// updated session, and returns it. Maps any refresh failure (e.g. the
    /// refresh token itself expired) to `sessionExpired` so the caller falls
    /// back to prompting a reconnect.
    private func refreshedSession(_ session: AulaSession) async throws -> AulaSession {
        guard let refreshToken = session.refreshToken else {
            throw AulaProviderError.sessionExpired
        }
        let tokens: TokenResponse
        do {
            tokens = try await tokenRefresher.refresh(refreshToken: refreshToken)
        } catch {
            throw AulaProviderError.sessionExpired
        }
        var updated = session
        updated.accessToken = tokens.accessToken
        if let newRefreshToken = tokens.refreshToken {
            updated.refreshToken = newRefreshToken
        }
        updated.expiresAt = tokens.expiresIn.map {
            Date.now.addingTimeInterval(TimeInterval($0))
        }
        credentialStore.save(updated, for: integrationID)
        return updated
    }

    /// Attempts a silent re-authorize against the session's persisted broker
    /// cookies, merges the result (fresh tokens, when minted, plus the
    /// re-warmed API/broker cookie jars) into the session, and persists it.
    /// Returns `nil` when there's no broker jar to recover with — a session
    /// connected before this existed, or one where the earlier interactive
    /// login never captured one — so the caller falls straight through to
    /// `sessionExpired`. Any re-authorize failure (most commonly the broker
    /// session itself having lapsed) also surfaces as `nil`.
    private func reauthorizedSession(_ session: AulaSession) async throws -> AulaSession? {
        guard let brokerCookies = session.brokerCookies, !brokerCookies.isEmpty else {
            return nil
        }
        let result: AulaReauthResult
        do {
            result = try await reauthorizer.reauthorize(
                brokerCookies: AulaSessionCookies.httpCookies(from: brokerCookies),
                userAgent: session.userAgent
            )
        } catch {
            return nil
        }

        var updated = session
        if let tokens = result.tokens {
            updated.accessToken = tokens.accessToken
            if let newRefreshToken = tokens.refreshToken {
                updated.refreshToken = newRefreshToken
            }
            updated.expiresAt = tokens.expiresIn.map {
                Date.now.addingTimeInterval(TimeInterval($0))
            }
        }
        updated.cookies = AulaSessionCookies.apiCookies(from: result.cookies)
        updated.brokerCookies = AulaSessionCookies.brokerCookies(from: result.cookies)
        credentialStore.save(updated, for: integrationID)
        return updated
    }

    /// Persists the returned session whenever it changed — the client bumps the
    /// API version on 410 and folds in Aula's rotated `PHPSESSID` on every
    /// response, both of which must survive to the next call (the rotated
    /// cookie is single-use, so dropping it 401s the following request).
    private func persisting(
        _ response: AulaResponse,
        against previous: AulaSession
    ) -> Data {
        if response.session != previous {
            credentialStore.save(response.session, for: integrationID)
        }
        return response.data
    }

    private func session() throws -> AulaSession {
        guard let session = credentialStore.read(for: integrationID) else {
            throw AulaProviderError.notAuthenticated
        }
        return session
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AulaProviderError.requestFailed("Unexpected Aula response")
        }
    }

    private static func isoDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }

    /// Aula rejects calendar queries spanning much more than a month (observed
    /// as a `403`). Cap the window so a caller's over-long range degrades to
    /// the most recent supported slice instead of failing outright.
    static let maxCalendarSpanDays = 21

    private static func cappingSpan(from: String, to: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd"
        guard let fromDate = parser.date(from: from),
              let toDate = parser.date(from: to)
        else { return to }

        let maxEnd = fromDate.addingTimeInterval(TimeInterval(maxCalendarSpanDays * 86400))
        return toDate <= maxEnd ? to : parser.string(from: maxEnd)
    }

    /// Normalizes a `YYYY-MM-DD` date to the exact timestamp shape Aula's
    /// calendar API expects — midnight, `2026-07-13 00:00:00.0000+0000` — the
    /// date-only form is rejected. Mirrors the community clients, which format
    /// both bounds at midnight; `endOfDay` advances to the *next* midnight so a
    /// single-day `from`/`to` still spans that whole day. A value already
    /// carrying a time is passed through unchanged.
    private static func aulaDateTime(_ dateString: String, endOfDay: Bool) -> String {
        let dateOnly = DateFormatter()
        dateOnly.locale = Locale(identifier: "en_US_POSIX")
        dateOnly.timeZone = TimeZone(identifier: "UTC")
        dateOnly.dateFormat = "yyyy-MM-dd"
        guard let date = dateOnly.date(from: dateString) else { return dateString }

        let full = DateFormatter()
        full.locale = Locale(identifier: "en_US_POSIX")
        full.timeZone = TimeZone(identifier: "UTC")
        full.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSZ"
        return full.string(from: date.addingTimeInterval(endOfDay ? 86400 : 0))
    }
}
