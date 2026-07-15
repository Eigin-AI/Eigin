import Foundation

/// Confirms a freshly-logged-in ``AulaSession`` actually works before we save
/// the integration — the Aula counterpart to the OAuth flows' token exchange
/// and ``IMAPConnectionVerifier``'s connect check.
///
/// It calls `profiles.getProfilesByLogin` through ``AulaAPIClient`` (so the
/// version-bump/cookie/csrf plumbing is exercised end to end), and returns the
/// session enriched with the guardian's children and any bumped API version —
/// that enriched session is what gets persisted, giving the agent family
/// context for free.
enum AulaConnectionVerifier {
    static func verify(
        session: AulaSession,
        apiClient: AulaAPIClient
    ) async throws -> AulaSession {
        let response: AulaResponse
        do {
            response = try await apiClient.get(
                method: "profiles.getProfilesByLogin",
                session: session
            )
        } catch let error as AulaProviderError {
            throw AulaConnectionError.from(error)
        }

        // Establish the active guardian profile in the session. Aula's
        // sensitive endpoints (messaging.getThreads, calendar) act on an
        // implicit active profile and reject calls made before one is
        // selected; the proven community clients all call this once at setup.
        // Best-effort: a failure here shouldn't block connecting, but it does
        // rotate/refresh the session cookies we go on to persist.
        // The web app sends a `profile_change` cookie (the active-profile
        // selector) on institution-scoped calls — messaging, calendar. The
        // community API walkthroughs set it client-side to a small constant;
        // without it those endpoints reject the request (observed as an Aula
        // envelope `code 20`). Seed it before the context probe so every call
        // from here on carries it.
        var contextSession = response.session
        if contextSession.cookies["profile_change"] == nil {
            contextSession.cookies["profile_change"] = "1"
        }
        if let contextResponse = try? await apiClient.get(
            method: "profiles.getProfileContext",
            queryItems: [URLQueryItem(name: "portalrole", value: "guardian")],
            session: contextSession
        ) {
            contextSession = contextResponse.session
        }

        guard let decoded = try? JSONDecoder().decode(
            AulaProfilesResponse.self,
            from: response.data
        ) else {
            throw AulaConnectionError.unexpectedResponse
        }

        let rawChildren = decoded.data.profiles.flatMap { $0.children ?? [] }
        var children: [AulaChild] = []
        for child in rawChildren {
            children.append(AulaChild(
                id: String(child.id),
                name: child.name ?? "",
                institution: child.institutionProfile?.institutionName ?? "",
                institutionProfileID: child.institutionProfile?.id
            ))
        }

        var enriched = contextSession
        enriched.children = children
        // The guardian's own institution-profile memberships, parallel to
        // each child's — both feed `posts.getAllPosts`'s
        // `institutionProfileIds[]` (see `DefaultAulaProvider.fetchPosts`),
        // without which Aula scopes the feed to a narrow default.
        enriched.guardianInstitutionProfileIDs = decoded.data.profiles
            .flatMap { $0.institutionProfiles?.map(\.id) ?? [] }
        return enriched
    }
}

/// User-facing: surfaced in ``AddAulaAccount``'s error UI, so localized —
/// same convention as ``IMAPConnectionError``.
enum AulaConnectionError: Error, LocalizedError, Equatable {
    case sessionRejected
    case unexpectedResponse
    case requestFailed(String)

    static func from(_ error: AulaProviderError) -> AulaConnectionError {
        switch error {
        case .sessionExpired, .notAuthenticated:
            .sessionRejected
        case .notFound:
            .unexpectedResponse
        case .requestFailed(let reason):
            .requestFailed(reason)
        }
    }

    var errorDescription: String? {
        switch self {
        case .sessionRejected:
            Localized.Errors.Aula.sessionRejected
        case .unexpectedResponse:
            Localized.Errors.Aula.unexpectedResponse
        case .requestFailed(let reason):
            Localized.Errors.Aula.requestFailed(reason)
        }
    }
}
