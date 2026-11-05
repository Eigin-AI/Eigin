import Foundation
import SwiftData

/// Resolves a chat without returning a pending deletion or a stale retained model.
@MainActor
enum ChatLookup {
    static func find(_ id: UUID, in context: ModelContext) -> Chat? {
        let descriptor = FetchDescriptor<Chat>(predicate: #Predicate { $0.id == id })
        guard let chat = try? context.fetch(descriptor).first,
              !chat.isDeleted, chat.modelContext != nil else { return nil }
        return chat
    }
}
