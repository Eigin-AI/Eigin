import SwiftUI

// Developer-only view for inspecting and clearing on-device model storage.
//
// Over the course of development multiple model variants can accumulate on
// disk (different model quantizations, stale Gemma downloads from earlier
// iterations, etc). This view lists the known model directories with their
// actual disk usage and offers a delete button for each, plus a nuclear
// "clear everything in caches" option.
#if DEBUG
struct ModelStorageView: View {
    @State private var entries: [StorageEntry] = []
    @State private var isDeleting = false

    var body: some View {
        List {
            Section("On-device model storage") {
                if entries.isEmpty {
                    Text(Localized.Debug.scanning)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            HStack {
                                Text(entry.name)
                                    .font(Typography.body)
                                Spacer()
                                Text(entry.formattedSize)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.path)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if entry.exists {
                                Button(role: .destructive) {
                                    Task { await delete(entry) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                        .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(isDeleting)
                            }
                        }
                        .padding(.vertical, Spacing.xs)
                    }
                }
            }

            Section {
                HStack {
                    Text(Localized.Ui.total)
                        .font(Typography.body)
                    Spacer()
                    Text(ModelStorageView.formatBytes(totalBytes))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button(role: .destructive) {
                    Task { await deleteAll() }
                } label: {
                    Label("Delete all listed", systemImage: "trash.fill")
                }
                .disabled(isDeleting || entries.allSatisfy { !$0.exists })
            } footer: {
                Text(
                    Localized.Settings.ClearModelStorage.description
                )
            }
        }
        .navigationTitle("Model Storage")
        .navigationBarTitleDisplayMode(.inline)
        .task { refresh() }
        .refreshable { refresh() }
    }

    private var totalBytes: Int64 {
        entries.reduce(0) { $0 + $1.bytes }
    }

    // MARK: - Actions

    private func refresh() {
        entries = ModelStorageView.scan()
    }

    private func delete(_ entry: StorageEntry) async {
        isDeleting = true
        defer { isDeleting = false }
        // Also unload any in-memory model so we're not holding open files.
        switch entry.id {
        case "gemma":
            GemmaModelManager.shared.delete()
        default:
            try? FileManager.default.removeItem(atPath: entry.path)
        }
        refresh()
    }

    private func deleteAll() async {
        isDeleting = true
        defer { isDeleting = false }
        GemmaModelManager.shared.delete()
        for entry in entries where entry.id.hasPrefix("other:") {
            try? FileManager.default.removeItem(atPath: entry.path)
        }
        // Also try the library's built-in escape hatch for any stale
        // Gemma variants under Documents/Models that isn't gemma4-e2b.
        try? GemmaModelDownloader.shared.resetAllModels()
        refresh()
    }

    // MARK: - Scanning

    private struct StorageEntry: Identifiable {
        let id: String
        let name: String
        let path: String
        let bytes: Int64
        var exists: Bool {
            bytes > 0
        }

        var formattedSize: String {
            ModelStorageView.formatBytes(bytes)
        }
    }

    private static func scan() -> [StorageEntry] {
        var entries: [StorageEntry] = []
        let fm = FileManager.default

        // Gemma lives in Documents/Models/{folderName} via the library's
        // ModelDownloader.
        let gemmaURL = documentsURL()
            .appendingPathComponent("Models")
            .appendingPathComponent("gemma4-e2b")
        entries.append(StorageEntry(
            id: "gemma",
            name: Localized.Ui.gemma4E2bCoreml,
            path: gemmaURL.path,
            bytes: directorySize(at: gemmaURL)
        ))

        // Stale model artifacts from earlier iterations — scan only the
        // directories that could have held models:
        //   - Documents/Models/* (library layout, other model folder names)
        //   - Caches/* (old stash-based Gemma downloader wrote here)
        // We never scan Application Support root or Documents root, so
        // SwiftData's store and any app-owned files are never touched.
        let modelsDir = documentsURL().appendingPathComponent("Models")
        if let items = try? fm.contentsOfDirectory(atPath: modelsDir.path) {
            for item in items where item != "gemma4-e2b" {
                let url = modelsDir.appendingPathComponent(item)
                let size = directorySize(at: url)
                guard size > 50_000_000 else { continue }
                entries.append(StorageEntry(
                    id: "other:models:\(item)",
                    name: "Stale model: \(item)",
                    path: url.path,
                    bytes: size
                ))
            }
        }

        let caches = cachesURL()
        if let items = try? fm.contentsOfDirectory(atPath: caches.path) {
            for item in items {
                let url = caches.appendingPathComponent(item)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue
                else { continue }
                let size = directorySize(at: url)
                // Only surface directories large enough to matter.
                guard size > 100_000_000 else { continue }
                entries.append(StorageEntry(
                    id: "other:caches:\(item)",
                    name: "Stale cache: \(item)",
                    path: url.path,
                    bytes: size
                ))
            }
        }

        return entries
    }

    private static func documentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    private static func cachesURL() -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    }

    private static func appSupportURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    }

    private static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return 0 }
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [
                .totalFileAllocatedSizeKey,
                .fileAllocatedSizeKey,
            ])
            if let size = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize {
                total += Int64(size)
            }
        }
        return total
    }

    private nonisolated static func formatBytes(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 B" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview {
    NavigationStack {
        ModelStorageView()
    }
}
#endif
