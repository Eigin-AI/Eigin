import Foundation

/// Directories with a download in progress, so a relaunch can pick them up.
/// Stored relative to the app home; the container path can move between installs.
struct AssetDownloadRegistry {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = StorageKey.assetDownloadsInProgress) {
        self.defaults = defaults
        self.key = key
    }

    func directories() -> [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory())
        return (defaults.stringArray(forKey: key) ?? []).map { home.appendingPathComponent($0) }
    }

    func add(_ directory: URL) {
        var entries = defaults.stringArray(forKey: key) ?? []
        let relative = Self.relativePath(directory)
        guard !entries.contains(relative) else { return }
        entries.append(relative)
        defaults.set(entries, forKey: key)
    }

    func remove(_ directory: URL) {
        let relative = Self.relativePath(directory)
        let entries = (defaults.stringArray(forKey: key) ?? []).filter { $0 != relative }
        defaults.set(entries, forKey: key)
    }

    private static func relativePath(_ directory: URL) -> String {
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL.path
        let path = directory.standardizedFileURL.path
        guard path.hasPrefix(home) else { return path }
        return String(path.dropFirst(home.count)).trimmingCharacters(in: ["/"])
    }
}
