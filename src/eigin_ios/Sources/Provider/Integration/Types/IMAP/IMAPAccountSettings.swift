import Foundation

/// Server settings + credentials for a manually configured IMAP/SMTP email
/// account (e.g. iCloud, Fastmail, Proton via bridge).
///
/// Persisted as a single JSON blob in the Keychain (see
/// ``IMAPCredentialStore``) rather than split across fields on the
/// ``Integration`` model — it holds the password, so the whole thing is
/// secret-adjacent, and keeping it together avoids a schema migration for
/// what's fundamentally one unit of connection state.
struct IMAPAccountSettings: Codable, Equatable, Sendable {
    /// The account's own address, used as the `From` on sent mail and as the
    /// fallback username for both IMAP and SMTP.
    var emailAddress: String
    var imapHost: String
    var imapPort: Int
    var smtpHost: String
    var smtpPort: Int
    /// Usually the same as `emailAddress`, but some providers (e.g. iCloud)
    /// want a separate "mail name" for IMAP login.
    var imapUsername: String
    var smtpUsername: String
    /// An app-specific password where the provider requires one (iCloud,
    /// Gmail-via-IMAP, etc.) rather than the account's normal password.
    var password: String

    static let defaultIMAPPort = 993
    static let defaultSMTPPort = 587

    init(
        emailAddress: String,
        imapHost: String,
        imapPort: Int = IMAPAccountSettings.defaultIMAPPort,
        smtpHost: String,
        smtpPort: Int = IMAPAccountSettings.defaultSMTPPort,
        imapUsername: String? = nil,
        smtpUsername: String? = nil,
        password: String
    ) {
        self.emailAddress = emailAddress
        self.imapHost = imapHost
        self.imapPort = imapPort
        self.smtpHost = smtpHost
        self.smtpPort = smtpPort
        self.imapUsername = imapUsername ?? emailAddress
        self.smtpUsername = smtpUsername ?? emailAddress
        self.password = password
    }
}
