@testable import Eigin
import Foundation
import Testing

@Suite("Speech DSP")
struct SpeechDSPTests {
    private let sampleRate = 48000.0

    private func sine(frequency: Float, amplitude: Float, samples: Int) -> [Float] {
        (0 ..< samples).map {
            amplitude * sin(2 * Float.pi * frequency * Float($0) / Float(sampleRate))
        }
    }

    private func peak(_ samples: [Float]) -> Float {
        samples.map(abs).max() ?? 0
    }

    // MARK: - Makeup gain

    @Test func makeupGainScalesByExactlyTheConfiguredAmount() {
        let config = SpeechDSPConfig(makeupGainDecibels: 6, highShelf: nil, limiterCeiling: 2.0)
        let dsp = SpeechDSPProcessor(config: config, sampleRate: sampleRate)
        var samples = sine(frequency: 200, amplitude: 0.1, samples: 4800)
        dsp.process(&samples)
        #expect(abs(peak(samples) - 0.1 * pow(10, 6 / 20)) < 1e-4)
    }

    // MARK: - High shelf

    @Test func shelfBoostsHighFrequencies() {
        // Limiter and makeup gain off; shelf alone at +6 dB above 5 kHz.
        let config = SpeechDSPConfig(
            makeupGainDecibels: 0,
            highShelf: .init(cornerFrequency: 5000, gainDecibels: 6),
            limiterCeiling: 2.0
        )
        let dsp = SpeechDSPProcessor(config: config, sampleRate: sampleRate)
        var samples = sine(frequency: 8000, amplitude: 0.25, samples: 9600)
        dsp.process(&samples)
        // Steady-state amplitude should approach 2x (+6 dB).
        let tail = Array(samples.dropFirst(samples.count / 2))
        #expect(peak(tail) > 0.45)
    }

    @Test func shelfLeavesLowFrequenciesUntouched() {
        let config = SpeechDSPConfig(
            makeupGainDecibels: 0,
            highShelf: .init(cornerFrequency: 5000, gainDecibels: 6),
            limiterCeiling: 2.0
        )
        let dsp = SpeechDSPProcessor(config: config, sampleRate: sampleRate)
        var samples = sine(frequency: 300, amplitude: 0.25, samples: 9600)
        dsp.process(&samples)
        let tail = Array(samples.dropFirst(samples.count / 2))
        #expect(abs(peak(tail) - 0.25) < 0.02)
    }

    // MARK: - Limiter

    @Test func limiterNeverExceedsCeiling() {
        let config = SpeechDSPConfig(makeupGainDecibels: 12, highShelf: nil, limiterCeiling: 0.5)
        let dsp = SpeechDSPProcessor(config: config, sampleRate: sampleRate)
        var samples = sine(frequency: 440, amplitude: 0.9, samples: 48000)
        dsp.process(&samples)
        #expect(peak(samples) <= 0.5)
    }

    @Test func limiterPassesQuietSignalUntouched() {
        let config = SpeechDSPConfig(makeupGainDecibels: 0, highShelf: nil, limiterCeiling: 0.5)
        let dsp = SpeechDSPProcessor(config: config, sampleRate: sampleRate)
        var samples = sine(frequency: 440, amplitude: 0.2, samples: 4800)
        dsp.process(&samples)
        #expect(abs(peak(samples) - 0.2) < 1e-4)
    }

    // MARK: - Streaming chunk continuity

    @Test func chunkedProcessingMatchesWholeBufferProcessing() {
        let config = SpeechDSPConfig(
            makeupGainDecibels: 6,
            highShelf: .init(cornerFrequency: 5000, gainDecibels: 3),
            limiterCeiling: 0.5
        )
        let whole = sine(frequency: 440, amplitude: 0.4, samples: 48000)

        let wholeDSP = SpeechDSPProcessor(config: config, sampleRate: sampleRate)
        var wholeOut = whole
        wholeDSP.process(&wholeOut)

        // Feed the same signal in ~80 ms chunks, as the synthesizers do.
        let chunkDSP = SpeechDSPProcessor(config: config, sampleRate: sampleRate)
        var chunkOut = whole
        let chunkSize = 3840 // 80 ms at 48 kHz
        var start = 0
        while start < chunkOut.count {
            let end = min(start + chunkSize, chunkOut.count)
            var chunk = Array(chunkOut[start ..< end])
            chunkDSP.process(&chunk)
            chunkOut.replaceSubrange(start ..< end, with: chunk)
            start = end
        }

        #expect(chunkOut.count == wholeOut.count)
        for (a, b) in zip(chunkOut, wholeOut) {
            #expect(abs(a - b) < 1e-5)
        }
    }

    // MARK: - Marker safety

    @Test func oneSampleMarkerStaysSilent() {
        let config = SpeechDSPConfig(
            makeupGainDecibels: 12,
            highShelf: .init(cornerFrequency: 5000, gainDecibels: 6),
            limiterCeiling: 0.5
        )
        let dsp = SpeechDSPProcessor(config: config, sampleRate: sampleRate)
        var marker: [Float] = [0]
        dsp.process(&marker)
        #expect(marker == [0])
    }

    // MARK: - Session reset

    @Test func freshProcessorStartsClean() {
        let config = SpeechDSPConfig(makeupGainDecibels: 0, highShelf: nil, limiterCeiling: 0.5)
        // First processor sees a hot signal and engages the limiter.
        let first = SpeechDSPProcessor(config: config, sampleRate: sampleRate)
        var hot = sine(frequency: 440, amplitude: 0.9, samples: 4800)
        first.process(&hot)

        // A new session's quiet audio must pass through untouched — no
        // carry-over gain reduction state.
        let second = SpeechDSPProcessor(config: config, sampleRate: sampleRate)
        var quiet = sine(frequency: 440, amplitude: 0.2, samples: 4800)
        second.process(&quiet)
        #expect(abs(peak(quiet) - 0.2) < 1e-4)
    }
}
