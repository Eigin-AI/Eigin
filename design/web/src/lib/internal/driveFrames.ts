/**
 * Drives a tick-based model from animation frames until it settles.
 *
 * The models it drives — the stream throttler, the progress chaser — take time
 * as an argument so they can be stepped by hand in tests. This supplies the
 * real clock, in seconds, to match their timebase.
 *
 * The tick receives the animation frame's timestamp — milliseconds since the
 * page began, as handed out by requestAnimationFrame — converted to seconds.
 *
 * Returns a stop function; call it when the consumer goes away.
 */
export function driveFrames(
  tick: (timestamp: number) => void,
  isRunning: () => boolean,
): () => void {
  let frame = 0;

  const step = (now: number) => {
    tick(now / 1000);
    // Ask after ticking: this frame may be the one that settles it.
    frame = isRunning() ? requestAnimationFrame(step) : 0;
  };

  frame = requestAnimationFrame(step);

  return () => {
    if (frame) cancelAnimationFrame(frame);
    frame = 0;
  };
}
