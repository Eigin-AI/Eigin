import Foundation

/// A provider-scoped folder or Gmail label. IDs are opaque within the account.
struct EmailFolder: Sendable, Equatable {
    let id: String
    let name: String
    let parentID: String?

    var jsonObject: [String: Any] {
        var result: [String: Any] = ["id": id, "name": name]
        if let parentID { result["parent_id"] = parentID }
        return result
    }
}

extension EmailProvider {
    func listFolders() async throws -> [EmailFolder] {
        throw EmailProviderError.requestFailed("Folder access is unsupported by this provider.")
    }
}
