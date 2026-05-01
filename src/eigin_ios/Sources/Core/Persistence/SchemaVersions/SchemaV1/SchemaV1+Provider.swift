import Foundation
import SwiftData

extension SchemaV1 {
    @Model
    final class Provider {
        var id: UUID
        var name: String
        var baseURL: String
        var availableModels: [String] = []
        var enabledModels: [String] = []
        var createdAt: Date
        var updatedAt: Date

        init(name: String, baseURL: String) {
            id = UUID()
            self.name = name
            self.baseURL = baseURL
            createdAt = .now
            updatedAt = .now
        }
    }
}
