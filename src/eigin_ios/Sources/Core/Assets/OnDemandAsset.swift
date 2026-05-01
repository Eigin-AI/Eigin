import Foundation

/// State of a downloadable on-demand asset (model, voice pack, etc.).
enum AssetState: Equatable {
    case notDownloaded
    case downloading(fractionCompleted: Double)
    case downloaded
    case compiling(fractionCompleted: Double)
    case ready
    case failed(String)

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }

    var isCompiling: Bool {
        if case .compiling = self { return true }
        return false
    }
}

/// A downloadable asset that can be offered to the user as an upgrade.
///
/// Concrete implementations manage download, storage, and lifecycle
/// for a specific asset (e.g. a TTS model). The protocol provides
/// a uniform interface for the just-in-time download prompt and
/// settings UI.
@MainActor
protocol OnDemandAsset: AnyObject, Observable {
    /// Stable identifier for this asset.
    var id: String { get }
    /// User-facing name (e.g. "Enhanced Voice").
    var displayName: String { get }
    /// Description shown in the download prompt (e.g. "High-quality voice model (~300 MB)").
    var downloadDescription: String { get }
    /// Current download/readiness state.
    var state: AssetState { get }
    /// Whether the user has declined the download prompt. When true, don't prompt again.
    var hasBeenDeclined: Bool { get }

    /// Start downloading the asset.
    func download() async
    /// Delete the downloaded asset to reclaim storage.
    func delete()
    /// Record that the user declined the download prompt.
    func decline()
}

/// Identifiable wrapper for presenting an ``OnDemandAsset`` with `sheet(item:)`.
@MainActor
struct AssetItem: Identifiable {
    let id: String
    let asset: any OnDemandAsset

    init(_ asset: any OnDemandAsset) {
        id = asset.id
        self.asset = asset
    }
}
