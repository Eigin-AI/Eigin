import Foundation

/// Where each session task's bytes go on disk, readable from the session's
/// delegate queue. Keyed by `taskDescription`, which iOS persists with the
/// background task so it survives a relaunch.
final class AssetTaskTargets: @unchecked Sendable {
    struct Target {
        let path: String
        let destination: URL
        let part: AssetPart
    }

    private let lock = NSLock()
    private var targets: [String: Target] = [:]

    static func key(assetID: String, partIndex: Int) -> String {
        "\(assetID)|\(partIndex)"
    }

    static func parse(_ key: String) -> (assetID: String, partIndex: Int)? {
        guard let separator = key.lastIndex(of: "|"),
              let partIndex = Int(key[key.index(after: separator)...])
        else { return nil }
        return (String(key[..<separator]), partIndex)
    }

    @MainActor
    func register(_ job: AssetDownloadJob) {
        guard let plan = job.plan else { return }
        var entries: [String: Target] = [:]
        for (index, part) in plan.parts.enumerated() {
            entries[Self.key(assetID: job.request.assetID, partIndex: index)] = Target(
                path: plan.files[part.fileIndex].path,
                destination: job.request.directory
                    .appendingPathComponent(plan.localPaths[part.fileIndex]),
                part: part
            )
        }
        lock.withLock { targets.merge(entries) { _, new in new } }
    }

    func unregister(assetID: String) {
        let prefix = assetID + "|"
        lock.withLock { targets = targets.filter { !$0.key.hasPrefix(prefix) } }
    }

    /// Move a finished download's temp file into place: whole files replace
    /// the destination, ranges are written at their offset. Rejects error
    /// statuses and ranges the server ignored (a 200 body would be the whole
    /// file, not the slice we asked for).
    func place(downloadTask: URLSessionDownloadTask, from location: URL) -> Result<Void, Error> {
        defer { try? FileManager.default.removeItem(at: location) }
        guard let key = downloadTask.taskDescription,
              let target = lock.withLock({ targets[key] })
        else {
            return .failure(ModelAssetError.invalidURL(downloadTask.taskDescription ?? "?"))
        }

        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        if status >= 400 {
            let snippet = (try? String(contentsOf: location, encoding: .utf8))?
                .prefix(200).trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .failure(ModelAssetError.downloadFailed(
                path: target.path, status: status, detail: snippet
            ))
        }
        if !target.part.isWhole, status != 206 {
            return .failure(ModelAssetError.rangeNotHonoured(path: target.path))
        }
        // A short or mis-sliced body would only surface at the whole-file hash,
        // which then refetches every range of the file. Catch it per part.
        let received = (try? FileManager.default
            .attributesOfItem(atPath: location.path)[.size] as? Int64) ?? -1
        if received != target.part.length {
            return .failure(ModelAssetError.rangeNotHonoured(path: target.path))
        }

        do {
            let fm = FileManager.default
            if target.part.isWhole {
                try fm.createDirectory(
                    at: target.destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                if fm.fileExists(atPath: target.destination.path) {
                    try fm.removeItem(at: target.destination)
                }
                try fm.moveItem(at: location, to: target.destination)
            } else {
                try AssetFileWriter.write(
                    contentsOf: location, to: target.destination, at: target.part.offset
                )
            }
            return .success(())
        } catch {
            return .failure(error)
        }
    }
}
