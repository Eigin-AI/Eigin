import AudioToolbox
@preconcurrency import AVFoundation

/// Plays one-shot sounds for phase transitions.
///
/// Sounds are loaded from WAV files bundled in the app's Resources directory.
@MainActor
final class SoundManager {
    enum Sound: CaseIterable {
        case dictationStarted
        case dictationStopped
        case sending
        case waiting
        case attention
    }

    // MARK: - Players

    /// AVAudioPlayers are created lazily via `preparePlayers()` to avoid
    /// claiming the audio session (and the Bluetooth audio line) on init.
    private var players: [Sound: AVAudioPlayer] = [:]
    private var playersReady = false
    private var systemSoundIDs: [Sound: SystemSoundID] = [:]

    // MARK: - Init

    init() {
        for sound in Sound.allCases {
            guard let url = Self.url(for: sound) else { continue }
            var soundID: SystemSoundID = 0
            if AudioServicesCreateSystemSoundID(url as CFURL, &soundID) == noErr {
                systemSoundIDs[sound] = soundID
            }
        }
    }

    private static func url(for sound: Sound) -> URL? {
        let name = switch sound {
        case .dictationStarted: "ui_start"
        case .dictationStopped: "ui_stop"
        case .sending: "ui_send"
        case .waiting: "ui_wait"
        case .attention: "ui_attention"
        }
        return Bundle.main.url(forResource: name, withExtension: "wav")
    }

    deinit {
        for soundID in systemSoundIDs.values {
            AudioServicesDisposeSystemSoundID(soundID)
        }
    }

    // MARK: - Public API

    /// Pre-load AVAudioPlayers and acquire audio hardware.
    /// Call this before entering a live call so playback starts without delay.
    func preparePlayers() {
        guard !playersReady else { return }
        playersReady = true
        for sound in Sound.allCases {
            guard let url = Self.url(for: sound) else { continue }
            let player = try? AVAudioPlayer(contentsOf: url)
            player?.prepareToPlay()
            players[sound] = player
        }
    }

    /// Play sound as a UI effect. Respects the hardware silent/mute switch.
    func playUISound(_ sound: Sound) {
        guard let soundID = systemSoundIDs[sound] else { return }
        AudioServicesPlaySystemSound(soundID)
    }

    /// Play sound through AVAudioPlayer. Ignores the silent switch (for live calls).
    /// Requires a prior call to `preparePlayers()`.
    func play(_ sound: Sound, loops: Int = 0) {
        guard let player = players[sound] else { return }
        player.currentTime = 0
        player.volume = 0.25
        player.numberOfLoops = loops
        player.play()
    }

    func stop(_ sound: Sound) {
        guard let player = players[sound] else { return }
        player.stop()
    }

    /// Whether the sound is currently playing (for cue re-entry logic).
    func isPlaying(_ sound: Sound) -> Bool {
        players[sound]?.isPlaying == true
    }

    func stopAll() {
        for player in players.values {
            player.stop()
        }
    }
}
