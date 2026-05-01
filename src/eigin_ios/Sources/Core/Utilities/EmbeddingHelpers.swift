import Foundation
import NaturalLanguage

enum EmbeddingHelpers {
    /// Compute a sentence embedding by averaging word vectors from `NLEmbedding`.
    /// Returns `nil` if the embedding model is unavailable or no words are found.
    static func embed(_ text: String) -> [Double]? {
        // TODO: Use sentence embeddings instead where possible
        guard let embedding = NLEmbedding.wordEmbedding(for: .english) else { return nil }

        let dimension = embedding.dimension
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text

        var sum = [Double](repeating: 0, count: dimension)
        var count = 0

        tokenizer.enumerateTokens(in: text.startIndex ..< text.endIndex) { range, _ in
            let word = String(text[range])
            if let vector = embedding.vector(for: word) {
                for i in 0 ..< dimension {
                    sum[i] += vector[i]
                }
                count += 1
            }
            return true
        }

        guard count > 0 else { return nil }

        return sum.map { $0 / Double(count) }
    }

    /// Cosine similarity between two vectors. Returns 0 on mismatched or empty inputs.
    static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dot = 0.0
        var normA = 0.0
        var normB = 0.0

        for i in 0 ..< a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }

        return dot / denominator
    }
}
