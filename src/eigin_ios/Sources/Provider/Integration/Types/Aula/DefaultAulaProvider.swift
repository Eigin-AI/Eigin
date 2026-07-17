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

    init(
        integrationID: UUID,
        credentialStore: any AulaCredentialStore,
        apiClient: AulaAPIClient,
        tokenRefresher: any AulaTokenRefresher = DefaultAulaTokenRefresher()
    ) {
        self.integrationID = integrationID
        self.credentialStore = credentialStore
        self.apiClient = apiClient
        self.tokenRefresher = tokenRefresher
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
    /// The OAuth token is the session: web cookies (`PHPSESSID`, `Csrfp-Token`)
    /// are disposable server-side state that lapses independently of the token
    /// (Aula's web session is ~24h). So a `sessionExpired` from the API *call*
    /// — a `401`/`403` made with a valid access token — means that server-side
    /// web session has died, not the token. We recover once by dropping the
    /// stale cookies and priming a fresh server session (``resetWebSession``),
    /// letting the API re-issue web state via `Set-Cookie`, then retry the call
    /// against the primed session. A second failure propagates (no loop).
    ///
    /// A `sessionExpired` thrown by the proactive refresh grant itself, by
    /// contrast, means the refresh token's own lifetime ran out (the overnight
    /// case) — nothing a web-session reset can fix — so it propagates straight
    /// to an interactive reconnect without attempting a reset.
    private func withRefresh(
        _ call: (AulaSession) async throws -> AulaResponse
    ) async throws -> Data {
        var current = try session()
        // A refresh-grant failure here surfaces as `sessionExpired` before the
        // do/catch below, so it bypasses the web-session reset (a dead refresh
        // token isn't recoverable by re-priming cookies).
        if tokenExpired(current), current.refreshToken != nil {
            current = try await refreshedSession(current)
        }
        do {
            return try await persisting(call(current), against: current)
        } catch AulaProviderError.sessionExpired {
            AppLogger.debug("aula: sessionExpired, resetting web session", category: .network)
            guard let primed = try await resetWebSession(current) else {
                AppLogger.debug("aula: web-session reset unavailable or failed", category: .network)
                throw AulaProviderError.sessionExpired
            }
            AppLogger.debug("aula: web session reset, retrying call", category: .network)
            return try await persisting(call(primed), against: primed)
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
            AppLogger.debug(
                "aula: refresh grant failed: \(private: error.localizedDescription)",
                category: .network
            )
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

    /// Recovers from a `401`/`403` that means the server-side web session died
    /// (it lapses independently of the token). Drops all cookies, primes a
    /// fresh server session the way the reference client does, and lets the API
    /// re-issue web state via `Set-Cookie`. Returns the primed session, or
    /// `nil` when there's no token to reset onto (a cookie-only session can't
    /// be re-primed) or the prime itself fails — the caller then surfaces
    /// `sessionExpired` for an interactive reconnect.
    private func resetWebSession(_ session: AulaSession) async throws -> AulaSession? {
        guard session.accessToken != nil else { return nil } // nothing to reset onto
        var cleared = session
        cleared.cookies = [:]
        do {
            // Priming call: messaging endpoints 403 on an unprimed session (the
            // reference client establishes the active profile context before
            // getThreads). `absorbingCookies` captures the fresh PHPSESSID /
            // Csrfp-Token the response sets.
            let response = try await apiClient.get(
                method: "profiles.getProfileContext",
                queryItems: [URLQueryItem(name: "portalrole", value: "guardian")],
                session: cleared
            )
            credentialStore.save(response.session, for: integrationID)
            return response.session
        } catch {
            return nil // caller surfaces sessionExpired
        }
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
