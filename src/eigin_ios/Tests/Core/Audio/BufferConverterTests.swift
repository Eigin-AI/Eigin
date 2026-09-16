import AVFoundation
@testable import Eigin
import Testing

@Suite("BufferConverter")
struct BufferConverterTests {
    private func makeBuffer(sampleRate: Double, frameCount: AVAudioFrameCount) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let samples = buffer.floatChannelData![0]
        for i in 0 ..< Int(frameCount) {
            samples[i] = sin(Float(i) * 0.1)
        }
        return buffer
    }

    private var analyzerFormat: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
    }

    @Test("converts between formats")
    func converts() throws {
        let converter = BufferConverter()
        let input = makeBuffer(sampleRate: 22050, frameCount: 4096)

        let output = try converter.convert(input, to: analyzerFormat)

        #expect(output.format.sampleRate == 48000)
        #expect(output.frameLength > 0)
    }

    @Test("repeated conversions keep producing frames")
    func repeatedConversions() throws {
        // The .endOfStream from a previous conversion must not mark the
        // converter done — transcription feeds many chunks in sequence.
        let converter = BufferConverter()
        let input = makeBuffer(sampleRate: 22050, frameCount: 1024)

        let first = try converter.convert(input, to: analyzerFormat)
        let second = try converter.convert(input, to: analyzerFormat)
        let third = try converter.convert(input, to: analyzerFormat)

        #expect(first.frameLength > 0)
        #expect(second.frameLength > 0)
        #expect(third.frameLength > 0)
    }

    @Test("resampling scales the frame count")
    func resamples() throws {
        let converter = BufferConverter()
        // 22050 → 48000 upsampled — in the right ballpark, with slop for the
        // converter's priming frames.
        let input = makeBuffer(sampleRate: 22050, frameCount: 4800)

        let output = try converter.convert(input, to: analyzerFormat)

        let expected = Double(4800) * 48000 / 22050
        #expect(abs(Double(output.frameLength) - expected) < expected * 0.25)
    }
}
