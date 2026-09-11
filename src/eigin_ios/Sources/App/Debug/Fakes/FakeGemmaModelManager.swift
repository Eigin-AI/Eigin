#if DEBUG || EIGIN_DEV
import Observation

/// Fake ``GemmaModelManaging`` for screenshots and tests: reports a fixed
/// state without a model on disk, never touches the relay or the engine.
@MainActor
@Observable
final class FakeGemmaModelManager: GemmaModelManaging {
    let id = "fake-gemma"
    let displayName = "Fake model"
    let downloadDescription = ""
    var sizeDescription: String?
    var hasBeenDeclined = false
    var isSupported = true
    var state: AssetState

    init(state: AssetState = .ready) {
        self.state = state
    }

    func prepareIfNeeded() {}
    func download() async {}
    func compile() async {}
    func cancel() {}
    func delete() {}
    func decline() {
        hasBeenDeclined = true
    }
}
#endif
