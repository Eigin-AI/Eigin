@testable import Eigin
import Foundation
import Testing

/// Verifies that a capability is only considered granted when every scope it
/// requires was actually approved \u2014 Google's consent screen lets scopes be
/// denied individually, so a completed OAuth flow doesn't imply full consent.
@Suite("IntegrationType Grant Computation")
struct IntegrationTypeGrantTests {
    @Test func allRequiredScopesGrantedMeansCapabilityGranted() {
        let google = BundledIntegrationType.google
        let granted = google.grantedCapabilities(fromGrantedScopes: [
            "https://www.googleapis.com/auth/gmail.readonly",
            "https://www.googleapis.com/auth/gmail.send",
        ])
        #expect(granted.contains(.email))
    }

    @Test func missingOneScopeMeansCapabilityNotGranted() {
        let google = BundledIntegrationType.google
        // User approved read but denied send.
        let granted = google.grantedCapabilities(fromGrantedScopes: [
            "https://www.googleapis.com/auth/gmail.readonly",
        ])
        #expect(!granted.contains(.email))
    }

    @Test func noScopesGrantedMeansNoCapabilities() {
        let google = BundledIntegrationType.google
        let granted = google.grantedCapabilities(fromGrantedScopes: [])
        #expect(granted.isEmpty)
    }

    @Test func microsoftAllRequiredScopesGrantedMeansCapabilityGranted() {
        let microsoft = BundledIntegrationType.microsoft
        let granted = microsoft.grantedCapabilities(fromGrantedScopes: [
            "Mail.Read", "Mail.Send", "offline_access", "User.Read",
        ])
        #expect(granted.contains(.email))
    }

    @Test func microsoftMissingSendScopeMeansCapabilityNotGranted() {
        let microsoft = BundledIntegrationType.microsoft
        // User approved read but denied send.
        let granted = microsoft.grantedCapabilities(fromGrantedScopes: ["Mail.Read"])
        #expect(!granted.contains(.email))
    }
}
