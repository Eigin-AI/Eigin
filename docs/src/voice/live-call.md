# Live call

Live call mode runs a turn-based voice conversation:

1. **Listening**: records speech via dictation, watching for silence.
2. **Processing**: on silence, sends the transcribed text to the model.
3. **Speaking**: the response streams into TTS and the user hears the reply.
4. Back to listening.

Silence detection runs on a timer with configurable thresholds (fast/balanced/slow), so users choose how quickly the agent takes its turn.

## Background operation

Live call uses the platform's call framework to keep the session alive when the device is locked, showing native call UI on the lock screen with the agent's name and symbol. API keys are pre-fetched while unlocked and cached in memory, so the agent keeps responding with the screen off.
