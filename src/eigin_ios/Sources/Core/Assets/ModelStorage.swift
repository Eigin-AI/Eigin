import Foundation

/// Where downloaded model assets live on disk: `Documents/Models/<asset id>`.
///
/// Documents rather than Caches so iOS never purges multi-GB weights, and
/// excluded from backup because they're re-downloadable.
enum ModelStorage {
    static var rootDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Models")
    }

    static func directory(for assetID: String) -> URL {
        rootDirectory.appendingPathComponent(assetID)
    }

    /// Remove every model under the root — an escape hatch for stale artifacts.
    static func resetAll() throws {
        guard FileManager.default.fileExists(atPath: rootDirectory.path) else { return }
        try FileManager.default.removeItem(at: rootDirectory)
    }

    /// Keep the root out of iCloud/iTunes backups. Idempotent.
    static func excludeFromBackup() {
        var dir = rootDirectory
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try dir.setResourceValues(values)
        } catch {
            AppLogger.warning(
                "ModelStorage: could not exclude Models from backup: \(public: error.localizedDescription)",
                category: .chat
            )
        }
    }
}
