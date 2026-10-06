@testable import Eigin
import Foundation
import Security
import Testing

@Suite("OIDCTokenValidator")
struct OIDCTokenValidatorTests {
    /// Generates an RSA key pair, signs a JWT, and returns the token with a
    /// matching JWKS — the full RS256 verification path, no stubs.
    private func makeSignedToken(
        claims: [String: any Encodable & Sendable],
        kid: String = "test-key-1",
        tamper: Bool = false,
        rawPayloadJSON: String? = nil
    ) throws -> (token: String, jwks: OIDCTokenValidator.JWKS) {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let publicKey = SecKeyCopyPublicKey(privateKey)
        else {
            throw TestFailure
                .failure("RSA key generation failed: \(error?.takeRetainedValue() ?? nil)")
        }

        let headerJSON = #"{"alg":"RS256","kid":"\#(kid)"}"#
        var payloadJSON = rawPayloadJSON ?? {
            var json = "{"
            for (index, entry) in claims.enumerated() {
                json += index == 0 ? "" : ","
                let key = Self.jsonEscaped(entry.key)
                // Only string/number claim values used in these tests.
                if let number = entry.value as? Double {
                    json += "\"\(key)\":\(number)"
                } else {
                    json += "\"\(key)\":\"\(Self.jsonEscaped("\(entry.value)"))\""
                }
            }
            json += "}"
            return json
        }()

        let header = Self.base64URL(Data(headerJSON.utf8))
        let payload = Self.base64URL(Data(payloadJSON.utf8))
        let signingInput = "\(header).\(payload)"
        let signature = try #require(
            SecKeyCreateSignature(
                privateKey,
                .rsaSignatureMessagePKCS1v15SHA256,
                Data(signingInput.utf8) as CFData,
                &error
            ) as Data?
        )
        let signaturePart = tamper
            ? Self.base64URL(Data(repeating: 0, count: 256))
            : Self.base64URL(signature)

        let jwks = try OIDCTokenValidator.JWKS(keys: [Self.publicJWK(from: publicKey, kid: kid)])
        return (token: "\(signingInput).\(signaturePart)", jwks: jwks)
    }

    private enum TestFailure: Error {
        case failure(String)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func jsonEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Extracts the PKCS#1 `RSAPublicKey` DER integers back into a JWK.
    private static func publicJWK(from key: SecKey, kid: String) throws -> OIDCTokenValidator.JWK {
        var error: Unmanaged<CFError>?
        let der = try #require(SecKeyCopyExternalRepresentation(key, &error) as Data?)
        // PKCS#1 RSAPublicKey ::= SEQUENCE { modulus INTEGER, exponent INTEGER }
        let (modulus, exponent) = try #require(parseRSAPublicKey(der))
        return OIDCTokenValidator.JWK(
            kty: "RSA",
            kid: kid,
            modulus: base64URL(modulus),
            exponent: base64URL(exponent)
        )
    }

    /// Minimal DER reader for a PKCS#1 `RSAPublicKey`: consumes the outer
    /// SEQUENCE header, then reads its two INTEGER contents (modulus, exponent).
    private static func parseRSAPublicKey(_ der: Data) -> (Data, Data)? {
        var offset = der.startIndex
        /// Reads a length field at `offset`, advancing past it.
        func readLength() -> Int? {
            guard offset < der.endIndex else { return nil }
            var length = Int(der[offset])
            offset = der.index(after: offset)
            guard length & 0x80 == 0 else {
                let byteCount = length & 0x7F
                guard byteCount > 0, byteCount <= 4 else { return nil }
                length = 0
                for _ in 0 ..< byteCount {
                    guard offset < der.endIndex else { return nil }
                    length = length << 8 | Int(der[offset])
                    offset = der.index(after: offset)
                }
                return length
            }
            return length
        }

        // Outer SEQUENCE header.
        guard offset < der.endIndex, der[offset] == 0x30 else { return nil }
        offset = der.index(after: offset)
        guard let sequenceLength = readLength(),
              der.index(offset, offsetBy: sequenceLength) <= der.endIndex
        else { return nil }

        // Two INTEGERs inside: modulus, exponent.
        var integers: [Data] = []
        while offset < der.endIndex, integers.count < 2 {
            guard der[offset] == 0x02 else { return nil }
            offset = der.index(after: offset)
            guard let length = readLength(),
                  der.index(offset, offsetBy: length) <= der.endIndex
            else { return nil }
            integers.append(der.subdata(in: offset ..< der.index(offset, offsetBy: length)))
            offset = der.index(offset, offsetBy: length)
        }
        guard integers.count == 2, offset == der.endIndex else { return nil }
        return (integers[0], integers[1])
    }

    private let issuer = "https://auth.openai.com"

    // MARK: - Tests

    @Test func validTokenPassesFullValidation() throws {
        let (token, jwks) = try makeSignedToken(claims: [
            "iss": issuer,
            "aud": "oaiapp_test",
            "exp": Date.now.addingTimeInterval(600).timeIntervalSince1970,
            "nonce": "nonce-1",
            "sub": "user-1",
        ])

        let claims = try OIDCTokenValidator.validate(
            token,
            jwks: jwks,
            expectedIssuer: issuer,
            expectedAudience: "oaiapp_test",
            expectedNonce: "nonce-1"
        )
        #expect(claims.subject == "user-1")
    }

    @Test func tamperedSignatureFails() throws {
        let (token, jwks) = try makeSignedToken(claims: [
            "iss": issuer,
            "aud": "oaiapp_test",
            "exp": Date.now.addingTimeInterval(600).timeIntervalSince1970,
            "nonce": "nonce-1",
        ], tamper: true)

        #expect(throws: OIDCTokenValidator.ValidationError.signatureMismatch.self) {
            try OIDCTokenValidator.validate(
                token,
                jwks: jwks,
                expectedIssuer: issuer,
                expectedAudience: "oaiapp_test",
                expectedNonce: "nonce-1"
            )
        }
    }

    @Test func wrongAudienceNonceIssuerOrExpiryFail() throws {
        let (token, jwks) = try makeSignedToken(claims: [
            "iss": issuer,
            "aud": "oaiapp_test",
            "exp": Date.now.addingTimeInterval(600).timeIntervalSince1970,
            "nonce": "nonce-1",
        ])

        for (audience, nonce) in [("oaiapp_other", "nonce-1"), ("oaiapp_test", "nonce-other")] {
            #expect(throws: Error.self) {
                try OIDCTokenValidator.validate(
                    token,
                    jwks: jwks,
                    expectedIssuer: issuer,
                    expectedAudience: audience,
                    expectedNonce: nonce
                )
            }
        }

        #expect(throws: OIDCTokenValidator.ValidationError.issuerMismatch(
            expected: "https://other.example",
            actual: issuer
        ).self) {
            try OIDCTokenValidator.validate(
                token,
                jwks: jwks,
                expectedIssuer: "https://other.example",
                expectedAudience: "oaiapp_test",
                expectedNonce: "nonce-1"
            )
        }

        let expired = try makeSignedToken(claims: [
            "iss": issuer,
            "aud": "oaiapp_test",
            "exp": Date.now.addingTimeInterval(-600).timeIntervalSince1970,
            "nonce": "nonce-1",
        ])
        #expect(throws: OIDCTokenValidator.ValidationError.expired.self) {
            try OIDCTokenValidator.validate(
                expired.token,
                jwks: expired.jwks,
                expectedIssuer: issuer,
                expectedAudience: "oaiapp_test",
                expectedNonce: "nonce-1"
            )
        }
    }

    @Test func arrayAudienceClaimsValidate() throws {
        // JWT `aud` is string-or-array — an array containing the expected
        // client ID must not fail claims decoding ("malformed").
        let exp = Date.now.addingTimeInterval(600).timeIntervalSince1970
        let payload = """
        {"iss":"\(issuer)","aud":["oaiapp_test"],"exp":\(exp),"nonce":"nonce-1","sub":"user-1"}
        """
        #expect(payload.contains("\"aud\":[\"oaiapp_test\"]"))
        let (token, jwks) = try makeSignedToken(
            claims: [:],
            rawPayloadJSON: payload
        )

        let claims = try OIDCTokenValidator.validate(
            token,
            jwks: jwks,
            expectedIssuer: issuer,
            expectedAudience: "oaiapp_test",
            expectedNonce: "nonce-1"
        )
        #expect(claims.subject == "user-1")
        #expect(claims.audience == "oaiapp_test")
    }

    @Test func unknownSigningKeyFails() throws {
        let (token, _) = try makeSignedToken(claims: [
            "iss": issuer,
            "aud": "oaiapp_test",
            "exp": Date.now.addingTimeInterval(600).timeIntervalSince1970,
            "nonce": "nonce-1",
        ])
        let emptyJWKS = OIDCTokenValidator.JWKS(keys: [])

        #expect(throws: OIDCTokenValidator.ValidationError.unknownSigningKey.self) {
            try OIDCTokenValidator.validate(
                token,
                jwks: emptyJWKS,
                expectedIssuer: issuer,
                expectedAudience: "oaiapp_test",
                expectedNonce: "nonce-1"
            )
        }
    }
}
