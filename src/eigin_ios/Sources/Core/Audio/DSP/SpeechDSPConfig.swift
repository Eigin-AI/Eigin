/// Output processing settings a speech engine declares for its synthesized
/// audio. The same DSP chain runs for every engine; only the numbers differ.
struct SpeechDSPConfig: Sendable {
    struct HighShelf: Sendable, Equatable {
        /// Shelf corner in Hz; frequencies above this are lifted by `gainDecibels`.
        var cornerFrequency: Float
        var gainDecibels: Float

        init(cornerFrequency: Float, gainDecibels: Float) {
            self.cornerFrequency = cornerFrequency
            self.gainDecibels = gainDecibels
        }
    }

    /// Fixed makeup gain applied after the shelf.
    var makeupGainDecibels: Float

    /// High-shelf boost for top-end presence. Nil bypasses the filter.
    var highShelf: HighShelf?

    /// Peak ceiling in linear amplitude (~ -6 dBFS = 0.5) the limiter holds
    /// output to. Same for all engines — it's the safety net, not a creative tool.
    var limiterCeiling: Float

    init(
        makeupGainDecibels: Float,
        highShelf: HighShelf? = nil,
        limiterCeiling: Float = 0.5
    ) {
        self.makeupGainDecibels = makeupGainDecibels
        self.highShelf = highShelf
        self.limiterCeiling = limiterCeiling
    }
}
