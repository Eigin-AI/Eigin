import Foundation
import SwiftData

extension SchemaV7 {
    @Model
    final class Agent {
        var id: UUID
        var name: String
        var emoji: String
        @Attribute(originalName: "identityDocument") var identityCore: String
        @Attribute(originalName: "userDocument") var userCore: String
        @Attribute(originalName: "soulDocument") var soulCore: String
        var providerID: UUID
        var model: String
        /// When true, the model is chosen by ``ModelRouter`` rather than the user, and
        /// ``model`` holds whatever it most recently resolved. The provider stays the
        /// user's choice either way.
        var autoModel: Bool = true
        var voiceIdentifier: String?
        var proactivity: ProactivityLevel
        var bootstrapComplete: Bool = false
        var createdAt: Date
        var updatedAt: Date

        init(name: String, providerID: UUID, model: String) {
            id = UUID()
            self.name = name
            emoji = "🤖"
            identityCore = ""
            userCore = ""
            soulCore = ""
            self.providerID = providerID
            self.model = model
            proactivity = .reactive
            createdAt = .now
            updatedAt = .now
        }
    }
}
