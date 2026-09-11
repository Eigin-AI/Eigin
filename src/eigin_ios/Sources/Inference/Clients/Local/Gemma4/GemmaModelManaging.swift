import SwiftUI

/// The view-facing surface of ``GemmaModelManager``: read state plus the
/// lifecycle verbs the settings and onboarding screens drive.
///
/// Refines ``OnDemandAsset`` (which already covers `state`, display metadata,
/// `download`, `delete`, `decline`) with the Gemma-specific preparation calls.
/// Fakes inject their own manager through the environment so screens can
/// render model states without a model on disk.
@MainActor
protocol GemmaModelManaging: OnDemandAsset {
    /// Whether this device meets the minimum hardware requirements.
    var isSupported: Bool { get }

    /// Compiles the downloaded artifact if it hasn't been prepared yet.
    func prepareIfNeeded()

    /// Initialize the LiteRT engine for the downloaded model.
    func compile() async

    /// Cancels an in-flight download.
    func cancel()
}
