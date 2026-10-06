import Foundation
import Security

/// Validates OIDC ID tokens: RS256 signature against a JWKS endpoint, plus issuer,
/// audience, expiration, and nonce claims.
enum OIDCTokenValidator {
    struct Claims: Decodable, Equatable {
        let issuer: String
        let audience: String?
        let expiry: Double
        let nonce: String?
        let subject: String?

        enum CodingKeys: String, CodingKey {
            case issuer = "iss"
            case audience = "aud"
            case expiry = "exp"
            case nonce
            case subject = "sub"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            issuer = try container.decode(String.self, forKey: .issuer)
            // JWT `aud` is a string or an array of strings; first match wins.
            if let single = try? container.decodeIfPresent(String.self, forKey: .audience) {
                audience = single
            } else {
                audience = try? container.decodeIfPresent([String].self, forKey: .audience)?.first
            }
            expiry = try container.decode(Double.self, forKey: .expiry)
            nonce = try container.decodeIfPresent(String.self, forKey: .nonce)
            subject = try container.decodeIfPresent(String.self, forKey: .subject)
        }
    }

    enum ValidationError: LocalizedError, Equatable {
        case malformedToken
        case unknownSigningKey
        case signatureMismatch
        case expired
        case issuerMismatch(expected: String, actual: String)
        case audienceMismatch(expected: String, actual: String?)
        case nonceMismatch
        case jwksUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .malformedToken: "Malformed ID token."
            case .unknownSigningKey: "ID token signed with an unknown key."
            case .signatureMismatch: "ID token signature is invalid."
            case .expired: "ID token is expired."
            case .issuerMismatch(let expected, let actual):
                "ID token issuer mismatch: expected \(expected), got \(actual)."
            case .audienceMismatch(let expected, let actual):
                "ID token audience mismatch: expected \(expected), got \(actual ?? "none")."
            case .nonceMismatch: "ID token nonce mismatch."
            case .jwksUnavailable(let detail): "Could not load signing keys: \(detail)."
            }
        }
    }

    static let clockSkew: TimeInterval = 60

    /// Fetches the JWKS and fully validates `token`'s RS256 signature and claims.
    static func validate(
        _ token: String,
        jwksURL: URL,
        expectedIssuer: String,
        expectedAudience: String,
        expectedNonce: String,
        session: URLSession = .shared,
        now: () -> Date = { _validatingNow }
    ) async throws -> Claims {
        let jwks = try await fetchJWKS(url: jwksURL, session: session)
        return try validate(
            token,
            jwks: jwks,
            expectedIssuer: expectedIssuer,
            expectedAudience: expectedAudience,
            expectedNonce: expectedNonce,
            now: now
        )
    }

    /// Validates an ID token against a known key set (the testable core — no network).
    static func validate(
        _ token: String,
        jwks: JWKS,
        expectedIssuer: String,
        expectedAudience: String,
        expectedNonce: String,
        now: () -> Date = { _validatingNow }
    ) throws -> Claims {
        let parts = token.split(separator: ".").map(String.init)
        guard parts.count == 3,
              let headerData = base64URLDecode(parts[0]),
              let payloadData = base64URLDecode(parts[1]),
              let signature = base64URLDecode(parts[2]),
              let header = try? JSONDecoder().decode(JWTHeader.self, from: headerData),
              let claims = try? JSONDecoder().decode(Claims.self, from: payloadData)
        else {
            // Segment shapes and header are diagnostic; the payload itself
            // carries account data and stays out of the log.
            let headerJSON = token.split(separator: ".").first
                .flatMap { base64URLDecode(String($0)) }
                .flatMap { String(data: $0, encoding: .utf8) }
            AppLogger.error(
                "ID token malformed: segments=\(public: parts.count) header=\(public: headerJSON ?? "-")",
                category: .network
            )
            throw ValidationError.malformedToken
        }

        guard header.alg == "RS256" else { throw ValidationError.malformedToken }

        // Signed payload = the full "header.payload" string, byte-for-byte.
        let signingInput = String(token.prefix(parts[0].count + 1 + parts[1].count))
        let signingData = Data(signingInput.utf8)

        guard let key = jwks.keys.first(where: { $0.kid == header.kid && $0.kty == "RSA" }) else {
            throw ValidationError.unknownSigningKey
        }
        guard let rsaKey = Self.rsaPublicKey(from: key) else {
            throw ValidationError.unknownSigningKey
        }

        var verifyError: Unmanaged<CFError>?
        let verified = SecKeyVerifySignature(
            rsaKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            signingData as CFData,
            signature as CFData,
            &verifyError
        )
        guard verified else { throw ValidationError.signatureMismatch }

        guard claims.issuer == expectedIssuer else {
            throw ValidationError.issuerMismatch(expected: expectedIssuer, actual: claims.issuer)
        }
        guard claims.audience == expectedAudience else {
            throw ValidationError.audienceMismatch(
                expected: expectedAudience,
                actual: claims.audience
            )
        }
        guard Date(timeIntervalSince1970: claims.expiry).timeIntervalSince(now()) > -clockSkew
        else {
            throw ValidationError.expired
        }
        guard claims.nonce == expectedNonce else { throw ValidationError.nonceMismatch }

        return claims
    }

    // MARK: - Network

    private static func fetchJWKS(url: URL, session: URLSession) async throws -> JWKS {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse,
                  (200 ... 299).contains(http.statusCode)
            else {
                throw ValidationError
                    .jwksUnavailable("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            }
            return try JSONDecoder().decode(JWKS.self, from: data)
        } catch let error as ValidationError {
            throw error
        } catch {
            throw ValidationError.jwksUnavailable(error.localizedDescription)
        }
    }

    // MARK: - Key handling

    struct JWTHeader: Decodable {
        let alg: String
        let kid: String?
    }

    struct JWKS: Decodable {
        let keys: [JWK]
    }

    struct JWK: Decodable {
        let kty: String
        let kid: String?
        let modulus: String
        let exponent: String

        enum CodingKeys: String, CodingKey {
            case kty, kid
            case modulus = "n"
            case exponent = "e"
        }
    }

    static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64 += "="
        }
        return Data(base64Encoded: base64)
    }

    /// Builds an RSA public `SecKey` from a JWK by encoding the modulus and exponent as a
    /// PKCS#1 `RSAPublicKey` DER structure — the format `SecKeyCreateWithData` accepts for
    /// `kSecAttrKeyTypeRSA` public keys. No new dependency.
    static func rsaPublicKey(from jwk: JWK) -> SecKey? {
        guard let modulus = base64URLDecode(jwk.modulus),
              let exponent = base64URLDecode(jwk.exponent)
        else { return nil }

        let der = derSequence(derInteger(modulus) + derInteger(exponent))
        var error: Unmanaged<CFError>?
        return SecKeyCreateWithData(
            der as CFData,
            [
                kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            ] as CFDictionary,
            &error
        )
    }

    // MARK: - Minimal DER encoding

    /// One-element DER TLV with minimal-length length octets.
    private static func derTLV(tag: UInt8, content: Data) -> Data {
        var data = Data([tag])
        if content.count < 0x80 {
            data.append(UInt8(content.count))
        } else {
            let count = UInt32(content.count)
            var lengthBytes: [UInt8] = []
            for shift in stride(from: 24, through: 0, by: -8) {
                lengthBytes.append(UInt8((count >> UInt32(shift)) & 0xFF))
            }
            let trimmed = Array(lengthBytes.drop { $0 == 0 })
            data.append(UInt8(0x80) | UInt8(trimmed.count))
            data.append(contentsOf: trimmed)
        }
        data.append(content)
        return data
    }

    private static func derSequence(_ content: Data) -> Data {
        derTLV(tag: 0x30, content: content)
    }

    /// DER INTEGER, positive: prepend a zero octet when the high bit is set or the value is empty.
    private static func derInteger(_ value: Data) -> Data {
        var content = value
        if let first = content.first, first & 0x80 != 0 {
            content.insert(0, at: 0)
        } else if content.isEmpty {
            content = Data([0])
        }
        return derTLV(tag: 0x02, content: content)
    }
}

private var _validatingNow: Date {
    Date()
}
