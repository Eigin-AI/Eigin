@testable import Eigin
import Testing

@Suite("PlaybackBuffer")
struct PlaybackBufferTests {
    @Test("Returns nil while accumulating below threshold")
    func appendReturnsNilUntilThreshold() {
        let sampleRate: Double = 48000
        // 0.1 seconds of audio = 4_800 samples.
        let samplesPerFrame = 4800
        var buffer = PlaybackBuffer(targetDuration: 0.25, sampleRate: sampleRate)

        let result1 = buffer.append(samples: Array(repeating: 0.0, count: samplesPerFrame))
        #expect(result1 == nil)

        let result2 = buffer.append(samples: Array(repeating: 0.0, count: samplesPerFrame))
        #expect(result2 == nil)
    }

    @Test("Returns all accumulated frames on first flush past threshold")
    func appendReturnsAllFramesOnFirstFlush() {
        let sampleRate: Double = 48000
        let samplesPerFrame = 6000 // 0.125 s per frame
        var buffer = PlaybackBuffer(targetDuration: 0.25, sampleRate: sampleRate)

        // Below threshold: 0.125 s → nil
        let result1 = buffer.append(samples: Array(repeating: 0.1, count: samplesPerFrame))
        #expect(result1 == nil)

        // Crossing threshold: 0.25 s total → should return both frames
        let result2 = buffer.append(samples: Array(repeating: 0.2, count: samplesPerFrame))
        #expect(result2 != nil)
        #expect(result2?.count == 2)
        #expect(result2?[0].first == 0.1)
        #expect(result2?[1].first == 0.2)
    }

    @Test("Returns single frame after threshold is crossed")
    func appendReturnsSingleFrameAfterFlush() {
        let sampleRate: Double = 48000
        let samplesPerFrame = 15000 // 0.3125 s — above 0.25 s threshold on first append
        var buffer = PlaybackBuffer(targetDuration: 0.25, sampleRate: sampleRate)

        // First append crosses threshold → returns one frame
        let result1 = buffer.append(samples: Array(repeating: 0.3, count: samplesPerFrame))
        #expect(result1 != nil)
        #expect(result1?.count == 1)
        #expect(result1?[0].first == 0.3)

        // Subsequent appends return the new frame immediately
        let result2 = buffer.append(samples: Array(repeating: 0.4, count: samplesPerFrame))
        #expect(result2 != nil)
        #expect(result2?.count == 1)
        #expect(result2?[0].first == 0.4)
    }

    @Test("Flush returns remaining buffered frames")
    func flushReturnsRemainingFrames() {
        let sampleRate: Double = 48000
        let samplesPerFrame = 4800 // 0.1 s each
        var buffer = PlaybackBuffer(targetDuration: 0.25, sampleRate: sampleRate)

        // Two frames below threshold
        _ = buffer.append(samples: Array(repeating: 0.5, count: samplesPerFrame))
        _ = buffer.append(samples: Array(repeating: 0.6, count: samplesPerFrame))

        // Flush should return both accumulated frames without starting playback
        let flushed = buffer.flush()
        #expect(flushed.count == 2)
        #expect(flushed[0].first == 0.5)
        #expect(flushed[1].first == 0.6)
    }

    @Test("Flush returns empty array when no frames buffered")
    func flushReturnsEmptyWhenNothingBuffered() {
        var buffer = PlaybackBuffer(targetDuration: 0.25, sampleRate: 48000)
        let flushed = buffer.flush()
        #expect(flushed.isEmpty)
    }

    @Test("Subsequent append after flush returns frame immediately")
    func appendAfterFlushReturnsImmediately() {
        let sampleRate: Double = 48000
        var buffer = PlaybackBuffer(targetDuration: 0.25, sampleRate: sampleRate)

        // Seed with a frame that doesn't cross threshold
        _ = buffer.append(samples: Array(repeating: 0.7, count: 10000))

        // Flush empties the buffer
        _ = buffer.flush()

        // Next append should return immediately (hasStarted is true after flush)
        let result = buffer.append(samples: Array(repeating: 0.8, count: 10000))
        #expect(result != nil)
        #expect(result?.count == 1)
        #expect(result?[0].first == 0.8)
    }

    @Test("Append with empty samples returns nil")
    func appendEmptySamplesReturnsNil() {
        var buffer = PlaybackBuffer(targetDuration: 0.25, sampleRate: 48000)
        let result = buffer.append(samples: [])
        #expect(result == nil)
    }
}
