import AVFoundation

/// Converts audio buffers between formats. Matches the pattern from
/// Apple's SpeechAnalyzer sample code.
final class BufferConverter: @unchecked Sendable {
    private var converter: AVAudioConverter?
    private var currentInputFormat: AVAudioFormat?

    func convert(_ buffer: AVAudioPCMBuffer, to outputFormat: AVAudioFormat) throws
        -> AVAudioPCMBuffer
    {
        let inputFormat = buffer.format

        // Recreate the converter if the input format changed (e.g. route change).
        if converter == nil || currentInputFormat != inputFormat {
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
            currentInputFormat = inputFormat
        }

        guard let converter else {
            throw NSError(
                domain: "BufferConverter", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Could not create audio converter"]
            )
        }

        let ratio = outputFormat.sampleRate / inputFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard capacity > 0,
              let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity)
        else {
            throw NSError(
                domain: "BufferConverter", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Could not create output buffer"]
            )
        }

        // Reset converter state before each conversion — without this,
        // the .endOfStream from a previous call permanently marks the
        // converter as "done" and subsequent conversions return 0 frames.
        converter.reset()

        var error: NSError?
        nonisolated(unsafe) var hasProvided = false
        converter.convert(to: output, error: &error) { _, outStatus in
            if hasProvided {
                outStatus.pointee = .endOfStream
                return nil
            }
            hasProvided = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error { throw error }
        return output
    }
}
