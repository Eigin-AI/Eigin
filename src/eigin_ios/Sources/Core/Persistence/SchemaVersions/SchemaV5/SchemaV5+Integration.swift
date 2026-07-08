import Foundation
import SwiftData

extension SchemaV5 {
    /// A connected instance of an ``IntegrationType`` (e.g. a Google account).
    ///
    /// Mirrors ``MCPServer``'s shape: metadata lives here, tokens live in the
    /// keychain (namespaced by `id` via `KeychainService.integrationKey`).
    @Model
    final class Integration {
        var id: UUID
        /// Matches an ``IntegrationType/id`` in the compile-time catalog.
        var typeID: String
        /// User-facing label for this connection, e.g. the connected account's email.
        var accountLabel: String
        /// Which of the type's capabilities this specific grant covers.
        var grantedCapabilities: [String]
        var isEnabled: Bool
        var createdAt: Date
        var updatedAt: Date

        init(
            id: UUID = UUID(),
            typeID: String,
            accountLabel: String,
            grantedCapabilities: [String],
            isEnabled: Bool = true
        ) {
            self.id = id
            self.typeID = typeID
            self.accountLabel = accountLabel
            self.grantedCapabilities = grantedCapabilities
            self.isEnabled = isEnabled
            createdAt = .now
            updatedAt = .now
        }
    }
}
