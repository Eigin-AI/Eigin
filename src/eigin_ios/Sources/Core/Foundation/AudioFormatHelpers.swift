import AVFoundation

/// Returns the current hardware input format by querying ``AVAudioSession``
/// directly. Falls back to the engine's `inputNode.outputFormat` when the
/// session reports an unusable rate.
///
/// After a Bluetooth route change, `inputNode.outputFormat(forBus:)` can
/// report stale sample rates (e.g. 48 kHz when the hardware switched to
/// 24 kHz HFP). The session's `sampleRate` and `inputNumberOfChannels`
/// are authoritative immediately after the route settles.
func authoritativeInputFormat(engine: AVAudioEngine) -> AVAudioFormat {
    let session = AVAudioSession.sharedInstance()
    let hwRate = session.sampleRate
    let channels = max(1, AVAudioChannelCount(session.inputNumberOfChannels))
    if hwRate > 0,
       let hwFormat = AVAudioFormat(
           standardFormatWithSampleRate: hwRate, channels: channels
       )
    {
        return hwFormat
    }
    return engine.inputNode.outputFormat(forBus: 0)
}
