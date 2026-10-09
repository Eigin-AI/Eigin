@testable import Eigin
import Foundation
import Testing

@Suite("SpeechFade")
struct SpeechFadeTests {
    private let sampleRate = 48000.0

    @Test func holdsNewestChunkUntilNextArrives() {
        // Zero fade disables all ramps — pure holding behavior.
        let fade = SpeechFade(sampleRate: sampleRate, fadeDuration: 0)
        #expect(fade.append(samples: [1, 2, 3], utteranceIndex: 0) == [])
        #expect(fade.append(samples: [4, 5, 6], utteranceIndex: 0) == [[1, 2, 3]])
        #expect(fade.append(samples: [7, 8, 9], utteranceIndex: 0) == [[4, 5, 6]])
    }

    @Test func fadesInStreamStart() throws {
        let fade = SpeechFade(sampleRate: sampleRate, fadeDuration: 0.010)
        _ = fade.append(samples: [Float](repeating: 1, count: 2000), utteranceIndex: 0)
        let out = fade.append(samples: [Float](repeating: 1, count: 2000), utteranceIndex: 0)

        // The first held chunk ramps up from silence over the fade.
        let fadeCount = Int(sampleRate * 0.010)
        #expect(try abs(#require(out[0].first)) < 0.01)
        #expect(try abs(#require(out[0][fadeCount - 1]) - 1) < 0.01)
        #expect(out[0].last == 1)
    }

    @Test func crossfadesSeamAtUtteranceBoundary() throws {
        let fadeCount = Int(sampleRate * 0.030) // default fade duration
        let fade = SpeechFade(sampleRate: sampleRate)
        // Chunks long enough that the stream fade-in doesn't reach the
        // boundary crossfade region.
        _ = fade.append(samples: [Float](repeating: 3, count: 4000), utteranceIndex: 0)
        let out = fade.append(samples: [Float](repeating: 50, count: 4000), utteranceIndex: 1)

        // First chunk released whole except its final `fade` samples,
        // which the seam carries over (crossfade shortens the join).
        #expect(out[0].count == 4000 - fadeCount)
        let seam = out[1]
        #expect(seam.count == min(fadeCount, 2000))

        // Seam is continuous: starts at the tail's level, ends at the head's.
        #expect(try abs(#require(seam.first) - 3) < 0.1)
        #expect(try abs(#require(seam.last) - 50) < 0.1)
    }

    @Test func flushFadesOutToZero() throws {
        let fade = SpeechFade(sampleRate: sampleRate, fadeDuration: 0.001)
        _ = fade.append(samples: [Float](repeating: 1, count: 1000), utteranceIndex: 0)
        let out = fade.flush()
        #expect(out.count == 1)
        #expect(out[0].count == 1000)
        #expect(try abs(#require(out[0].last)) < 0.01)
        // Nothing left after flush.
        #expect(fade.flush().isEmpty)
    }

    @Test func buttJoinsWhenOverlapIsTooShortToMix() {
        let fade = SpeechFade(sampleRate: sampleRate)
        _ = fade.append(samples: [1], utteranceIndex: 0)
        // One-sample overlap can't mix both sides — emit whole chunks.
        let out = fade.append(samples: [9], utteranceIndex: 1)
        #expect(out == [[1]])
        #expect(fade.flush() == [[9]])
    }

    @Test func fadedBoundaryFadesTailOutAndHeadIn() throws {
        let fadeCount = Int(sampleRate * 0.030)
        let fade = SpeechFade(sampleRate: sampleRate, crossfadeAtBoundary: false)
        _ = fade.append(samples: [Float](repeating: 3, count: 2000), utteranceIndex: 0)
        // Boundary: tail released with fade-out; head held with fade-in.
        let boundary = fade.append(
            samples: [Float](repeating: 50, count: 2000),
            utteranceIndex: 1
        )
        #expect(boundary.count == 1)
        #expect(boundary[0].count == 2000)
        #expect(try abs(#require(boundary[0].last)) < 0.01)

        // Next chunk of the same utterance releases the faded-in head: it
        // ramps up over the fade, then sits at the constant level.
        let head = fade.append(samples: [Float](repeating: 50, count: 2000), utteranceIndex: 1)
        #expect(head.count == 1)
        #expect(head[0].count == 2000)
        #expect(try abs(#require(head[0].first)) < 0.01)
        #expect(head[0][fadeCount - 1] == 50)
        #expect(head[0].last == 50)
    }

    @Test func preservesSampleCountAcrossLongStream() {
        let fade = SpeechFade(sampleRate: sampleRate)
        var input: [Float] = []
        var utterances: [Int] = []
        for i in 0 ..< 20 {
            let chunk = [Float](repeating: Float(i + 1), count: 384)
            input += chunk
            utterances += Array(repeating: i / 5, count: 384)
        }

        var collected: [Float] = []
        var consumed = 0
        for start in stride(from: 0, to: input.count, by: 384) {
            let chunk = Array(input[start ..< min(start + 384, input.count)])
            let utt = utterances[consumed]
            collected += fade.append(samples: chunk, utteranceIndex: utt).flatMap { $0 }
            consumed += chunk.count
        }
        collected += fade.flush().flatMap { $0 }

        // Crossfades shorten the timeline by the overlap at each boundary
        // (3 utterance boundaries, chunk-sized overlap since chunks are
        // shorter than the fade).
        #expect(collected.count == input.count - 3 * 384)
    }
}
