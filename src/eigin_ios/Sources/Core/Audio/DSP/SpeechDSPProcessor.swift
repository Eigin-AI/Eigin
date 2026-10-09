import Foundation

/// The shared speech DSP chain: high shelf → makeup gain → limiter.
///
/// One instance per generation session. State (filter history, limiter gain)
/// persists across the ~80 ms streaming chunks a synthesizer feeds it, so
/// processing a signal in chunks is identical to processing it whole.
/// Created fresh per session — no state leaks between speak sessions.
final class SpeechDSPProcessor {
    private let makeupGain: Float
    private let shelf: Biquad?
    private let ceiling: Float

    // Limiter smoothing: fast attack, slow release, per-sample.
    private let attackCoef: Float
    private let releaseCoef: Float
    private var gain: Float = 1

    /// - Parameters:
    ///   - sampleRate: sample rate of the audio after resampling (48 kHz).
    init(config: SpeechDSPConfig, sampleRate: Double) {
        makeupGain = pow(10, config.makeupGainDecibels / 20)
        shelf = config.highShelf.map {
            Biquad(
                highShelfCornerHz: $0.cornerFrequency,
                gainDecibels: $0.gainDecibels,
                sampleRate: sampleRate
            )
        }
        ceiling = config.limiterCeiling
        attackCoef = exp(-1 / (0.002 * Float(sampleRate)))
        releaseCoef = exp(-1 / (0.080 * Float(sampleRate)))
    }

    /// Processes a chunk in place, preserving chain state for the next chunk.
    func process(_ samples: inout [Float]) {
        shelf?.process(&samples)
        for i in samples.indices {
            samples[i] *= makeupGain
            // Peak limiter: track how much to pull the signal down so it
            // never exceeds the ceiling. Gain follows the target with a fast
            // attack and slow release; a sample-accurate clamp catches the
            // residual attack transient.
            let x = samples[i]
            let rect = abs(x)
            var target: Float = 1
            if rect * gain > ceiling {
                target = ceiling / rect
            }
            let coef = target < gain ? attackCoef : releaseCoef
            gain += (target - gain) * (1 - coef)
            var y = x * gain
            // Soft-knee ceiling: anything above the knee smoothly flattens
            // toward the ceiling instead of squaring off, so residual attack
            // transients round off rather than hard-clip.
            let knee = 0.15 * ceiling
            let kneeLow = ceiling - knee
            if y > kneeLow {
                let over = y - kneeLow
                y = kneeLow + knee * tanh(over / knee)
            } else if y < -kneeLow {
                let over = y + kneeLow
                y = -kneeLow - knee * tanh(-over / knee)
            }
            samples[i] = y
        }
    }
}
