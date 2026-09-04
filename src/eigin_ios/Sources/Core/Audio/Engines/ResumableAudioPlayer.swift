#if !targetEnvironment(simulator)
@preconcurrency import AVFoundation

/// An `AVAudioEngine` + `AVAudioPlayerNode` pair that survives audio route
/// changes without repeating or dropping the current utterance.
///
/// A route change (Bluetooth connect/disconnect, car handover) stops the
/// engine and discards every buffer still queued on the player node. This
/// player retains each scheduled buffer until it has played, so on
/// `handleRouteChange()` it can rebuild the engine and re-schedule only the
/// **unplayed** tail. Audio resumes where it left off, and the completion
/// handlers that drive `onWillSpeak`/`onFinish` fire exactly once — so the
/// caller's turn bookkeeping stays intact.
@MainActor
final class ResumableAudioPlayer {
    /// One scheduled buffer and the work to run once it has played.
    /// Reference type so the play-back completion can flip `played` in place.
    private final class Entry: @unchecked Sendable {
        let buffer: AVAudioPCMBuffer
        let completion: (() -> Void)?
        var played = false
        /// True once the entry has begun rendering — the player node runs its
        /// queue strictly in order, so the prior entry completing implies the
        /// next one started. Route-change clipping only applies to entries
        /// that began playing; fully unheard entries are requeued whole.
        var started = false

        init(buffer: AVAudioPCMBuffer, completion: (() -> Void)?) {
            self.buffer = buffer
            self.completion = completion
        }
    }

    private let format: AVAudioFormat
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?

    /// Buffers scheduled since the last played prefix, in play order.
    private var entries: [Entry] = []

    /// Invalidates stale completion callbacks. Bumped on rebuild and stop so
    /// callbacks from a torn-down player node become no-ops.
    private var epoch = 0

    init(sampleRate: Double) {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
    }

    /// Build and start the engine. No-op if already running.
    func start() throws {
        guard engine == nil else { return }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()
        player.play()
        self.engine = engine
        self.player = player
    }

    /// Schedule a buffer for playback, retaining it until it has played.
    /// `completion` runs on the main actor once the buffer finishes.
    func schedule(_ buffer: AVAudioPCMBuffer, completion: (() -> Void)? = nil) {
        let entry = Entry(buffer: buffer, completion: completion)
        entries.append(entry)
        prunePlayed()
        // Scheduling happens during active playback and the node runs its
        // queue in order, so a queue head begins rendering immediately.
        if entries.first === entry {
            entry.started = true
        }
        scheduleEntry(entry)
    }

    /// Rebuild the engine on the new route and resume the unplayed tail.
    /// The currently-playing buffer is dropped rather than replayed: it's
    /// partially heard, so replaying it from its start repeats a whole block
    /// (streaming speech queues one big buffer per paragraph block). Its
    /// completion still fires so the caller's bookkeeping stays intact, and
    /// fully unheard entries are requeued whole.
    func handleRouteChange() {
        // Bump first so callbacks from the old player node are ignored, then
        // rebuild and re-queue whatever hadn't played yet.
        epoch += 1
        player?.stop()
        engine?.stop()
        engine = nil
        player = nil

        let pending = entries.filter { !$0.played }
        var clipped: [Entry] = []
        if let head = pending.first, head.started {
            clipped.append(head)
        }
        entries = Array(pending.dropFirst(clipped.count))
        clipped.first?.completion?()

        do {
            try start()
        } catch {
            // The route may still be settling — retry once before giving up.
            do {
                try start()
            } catch {
                // Playback can't continue on the new route. Run every pending
                // completion so callers' counters drain and the turn completes
                // (speech skipped) instead of wedging forever.
                entries.removeAll()
                for entry in pending.dropFirst(clipped.count) {
                    entry.completion?()
                }
                return
            }
        }
        for entry in entries {
            scheduleEntry(entry)
        }
        // The rebuilt node starts rendering the head immediately.
        entries.first?.started = true
    }

    /// Stop playback and release everything. Pending callbacks become no-ops.
    func stop() {
        epoch += 1
        player?.stop()
        player?.reset()
        engine?.stop()
        engine = nil
        player = nil
        entries.removeAll()
    }

    // MARK: - Private

    private func scheduleEntry(_ entry: Entry) {
        guard let player else { return }
        let scheduledEpoch = epoch
        player.scheduleBuffer(entry.buffer, completionHandler: { [weak self, entry] in
            Task { @MainActor [weak self, entry] in
                guard let self, epoch == scheduledEpoch else { return }
                entry.played = true
                // The node runs its queue in order, so once this entry has
                // finished, the following one has started rendering.
                if let next = entries.first(where: { !$0.played && !$0.started }) {
                    next.started = true
                }
                entry.completion?()
            }
        })
    }

    /// Drop the played prefix so retention stays bounded to the unplayed tail.
    private func prunePlayed() {
        while let first = entries.first, first.played {
            entries.removeFirst()
        }
    }
}
#endif
