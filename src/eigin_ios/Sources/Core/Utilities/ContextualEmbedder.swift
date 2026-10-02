import Foundation
import NaturalLanguage

/// Sentence embeddings from the on-device `NLContextualEmbedding` model.
///
/// Uses the Latin-script model, whose single vector space covers Danish,
/// English, and most other Latin-script languages — English descriptors match
/// Danish (or other Nordic-language) queries cross-lingually. Non-Latin
/// scripts are out of scope.
///
/// Instances are cheap to share: one per owner (typically the ``SkillIndex``
/// actor), so embedding runs off the main thread without reaching for statics.
final class ContextualEmbedder: @unchecked Sendable {
    private let modelLock = NSLock()
    private nonisolated(unsafe) var cachedModel: NLContextualEmbedding?

    /// Loads the Latin-script model on first use, should the assets be on
    /// device; `nil` when the model is unavailable on this system.
    private func model() -> NLContextualEmbedding? {
        modelLock.lock()
        defer { modelLock.unlock() }
        if let cachedModel { return cachedModel }
        let created = NLContextualEmbedding(script: .latin)
        cachedModel = created
        return created
    }

    /// Whether the model's assets are downloaded. Callers fall back when false.
    var isAvailable: Bool {
        model()?.hasAvailableAssets ?? false
    }

    /// Mean-pooled token vector for `text`, or `nil` when the model's assets
    /// are unavailable, the model fails to load, or `text` has no tokens.
    func embed(_ text: String) -> [Double]? {
        guard let model = model(), !text.isEmpty, model.hasAvailableAssets else { return nil }

        // One embedding at a time: the NL model is shared mutable state, and
        // calls are short — serializing is simpler than auditing thread-safety
        // we can't verify.
        modelLock.lock()
        defer { modelLock.unlock() }

        do {
            try model.load()
        } catch {
            return nil
        }
        guard let result = try? model.embeddingResult(for: text, language: nil) else {
            return nil
        }

        var sum: [Double]?
        var count = 0
        result.enumerateTokenVectors(in: text.startIndex ..< text.endIndex) { vector, _ in
            if let current = sum {
                precondition(current.count == vector.count, "Token vectors must share a dimension")
                for i in current.indices {
                    sum?[i] += vector[i]
                }
            } else {
                sum = vector
            }
            count += 1
            return true
        }

        guard var mean = sum, count > 0 else { return nil }
        let divisor = Double(count)
        for i in mean.indices {
            mean[i] /= divisor
        }
        return mean
    }
}
