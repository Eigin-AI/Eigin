import Foundation

/// State of a downloadable on-demand asset (model, voice pack, etc.).
enum AssetState: Equatable {
    case notDownloaded
    /// Waiting in the downloader's FIFO queue behind another asset.
    case queued
    case downloading(AssetTransferInfo)
    /// Fully on disk but not yet ready to use (e.g. pending preparation).
    case downloaded
    /// Post-transfer work: checksum pass, engine build. Fraction when known
    /// (an indeterminate meter otherwise) — this phase is brief.
    case preparing(fractionCompleted: Double?)
    case ready
    /// Something went wrong mid-download; partial bytes are kept so a retry
    /// resumes where it left off.
    case failed(String)
    /// This device can't use the asset right now (RAM, storage). Informational —
    /// the reason is the user-facing copy, and there is no in-row action.
    case unavailable(String)

    var isDownloading: Bool {
        if case .downloading = self { return true }
        return false
    }

    /// Whether the asset is in a busy state that shouldn't be interrupted by
    /// another download attempt.
    var isBusy: Bool {
        switch self {
        case .queued, .downloading, .downloaded, .preparing:
            true
        case .notDownloaded, .ready, .failed, .unavailable:
            false
        }
    }
}

/// Byte-level transfer progress for a download, plus a time-left estimate.
/// The estimate is nil until the transfer has run long enough to establish a
/// stable rate (see ``TransferRateEstimator``).
struct AssetTransferInfo: Equatable {
    var fractionCompleted: Double
    var bytesCompleted: Int64
    var totalBytes: Int64
    var estimatedSecondsLeft: Double?
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
    /// Approximate on-disk size, for rows and offers (e.g. "~2.6 GB").
    var sizeDescription: String? { get }
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

extension OnDemandAsset {
    /// Approximate on-disk size for rows and offers. Conformers without a
    /// meaningful size omit it.
    var sizeDescription: String? {
        nil
    }

    /// Start any post-download preparation so an installed asset never sits
    /// in a busy state waiting for a particular screen to be opened.
    /// Default: nothing to do.
    func prepareIfNeeded() {}
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
