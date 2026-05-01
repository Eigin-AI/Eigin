import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Shared PKCE and browser-based auth utilities used by MCP OAuth and provider OAuth flows.
enum PKCEUtilities {
    /// Generates a cryptographically random code verifier (RFC 7636).
    static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    /// Derives an S256 code challenge from a code verifier (RFC 7636).
    static func generateCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }

    /// Generates a cryptographically random state parameter.
    static func generateState() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    /// Presents an `ASWebAuthenticationSession` and returns the callback URL.
    ///
    /// Throws ``AuthSessionError/userCancelled`` if the user dismisses the browser,
    /// or ``AuthSessionError/failed(_:)`` for other errors.
    @MainActor
    static func presentAuthSession(url: URL, callbackScheme: String = "eigin") async throws -> URL {
        // The context must be retained for the duration of the session because
        // ASWebAuthenticationSession.presentationContextProvider is weak.
        let context = AuthSessionPresentationContext()

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                // Prevent premature deallocation of the presentation context
                withExtendedLifetime(context) {}

                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin
                {
                    continuation.resume(throwing: AuthSessionError.userCancelled)
                } else if let error {
                    continuation
                        .resume(throwing: AuthSessionError.failed(error.localizedDescription))
                } else if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation
                        .resume(throwing: AuthSessionError.failed("No callback URL received"))
                }
            }

            session.presentationContextProvider = context
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    /// Errors from ``presentAuthSession(url:callbackScheme:)``.
    enum AuthSessionError: LocalizedError {
        case userCancelled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .userCancelled:
                Localized.Errors.Authentication.cancelled
            case .failed(let message):
                message
            }
        }
    }
}

// MARK: - Presentation Context

private final class AuthSessionPresentationContext: NSObject,
    ASWebAuthenticationPresentationContextProviding
{
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first!
        return scene.windows.first(where: \.isKeyWindow) ?? ASPresentationAnchor(windowScene: scene)
    }
}

// MARK: - Data Extension

extension Data {
    /// Base64 URL encoding without padding (RFC 4648 Section 5).
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
