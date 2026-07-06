# Voice

Voice is a primary interaction method in Eigin. The system provides on-device dictation, streaming text-to-speech, and a dedicated [live call mode](./live-call.md) for hands-free conversation.

## Dictation

On-device speech recognition, so speech never leaves the device. It gives live transcription with partial results as the user speaks, handles audio route changes (Bluetooth connect/disconnect), and auto-restarts recognition when it hits the system's per-segment time cap.

## Text-to-speech

The streaming speech service accepts LLM response deltas incrementally. As text streams in, it extracts complete sentences at punctuation boundaries and queues them for playback, so the agent starts talking as soon as it has a sentence ready.

Eigin ships a local TTS model per supported language, run on-device for noticeably higher quality than the OS system voices. Where a local model exists for the active language it's used automatically; otherwise the OS voice is the fallback. Local models download on demand, so nothing extra is bundled at install.

## Sound design

Phase transitions (start listening, stop dictation, waiting for response) play short sound effects. System sounds respect the hardware silent switch; call ambience sounds do not, so the experience works whether or not the device is silenced.
