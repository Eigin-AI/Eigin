# Live call

Live call mode orchestrates a turn-based voice conversation:

1. **Listening** — records speech via dictation, monitors for silence
2. **Processing** — silence detected, sends transcribed text to the LLM
3. **Speaking** — LLM response streams into TTS, user hears the reply
4. **Back to listening**

Silence detection runs on a timer with configurable thresholds (fast/balanced/slow) so users can choose how quickly the agent takes its turn.

## Background operation

Live call uses the platform's call framework to keep the session alive when the device is locked. The native call UI appears on the lock screen with the agent's name and emoji. API keys are pre-fetched while unlocked and cached in memory, so the agent can continue responding even with the screen off.
