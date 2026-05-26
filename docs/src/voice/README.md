# Voice

Voice is a primary interaction method in Eigin, not a novelty. The system provides on-device dictation, streaming text-to-speech, and a dedicated [live call mode](./live-call.md) for hands-free conversation with the agent.

## Dictation

The dictation service uses on-device speech recognition. Speech never leaves the device. It provides live transcription with partial results as the user speaks, handles audio route changes (Bluetooth connect/disconnect), and auto-restarts recognition tasks when they hit the system's per-segment time cap.

## Text-to-speech

The streaming speech service accepts LLM response deltas incrementally. As text streams in, it extracts complete sentences at punctuation boundaries and queues them for playback. This means speech starts before the full response is generated. The agent begins talking as soon as it has a sentence ready.

Eigin ships a local TTS model for each supported language. These run on-device and produce noticeably higher quality speech than the OS system voices. Where a local model is available for the active language, it is used automatically. Where it isn't, the OS voice is the fallback. Local models are downloaded on demand. Nothing extra is bundled at install time.

## Sound design

Phase transitions (start listening, stop dictation, waiting for response) play short sound effects. System sounds respect the hardware silent switch; call ambience sounds do not, so the experience works as expected whether the device is silenced or not.
