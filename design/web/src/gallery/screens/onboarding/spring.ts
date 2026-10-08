/**
 * A SwiftUI `.spring(duration:bounce:)` as a function of time: 0 at rest at
 * the start, settling on 1, overshooting on the way when it bounces.
 */
export function springCurve(duration: number, bounce = 0): (t: number) => number {
  const omega = (2 * Math.PI) / duration;
  const damping = 1 - bounce;
  return (t) => {
    if (t <= 0) return 0;
    if (damping >= 1) return 1 - (1 + omega * t) * Math.exp(-omega * t);
    const damped = omega * Math.sqrt(1 - damping * damping);
    const decay = Math.exp(-damping * omega * t);
    return 1 - decay * (Math.cos(damped * t) + ((damping * omega) / damped) * Math.sin(damped * t));
  };
}

/**
 * The same spring as a CSS `linear()` easing, so web motion lands with the
 * overshoot the app does.
 *
 * SwiftUI's duration is perceptual: the spring keeps settling after it. The
 * returned `ms` covers the whole settle, so use it as the transition length.
 */
export function spring(duration: number, bounce = 0): { easing: string; ms: number } {
  const at = springCurve(duration, bounce);
  const omega = (2 * Math.PI) / duration;
  // Settled once the envelope stays within 0.1% of rest.
  const settle = Math.min(duration * 4, Math.log(1000) / ((1 - bounce) * omega));
  const steps = 48;
  const points = Array.from({ length: steps + 1 }, (_, i) =>
    (i === steps ? 1 : at((settle * i) / steps)).toFixed(4),
  );
  return { easing: `linear(${points.join(", ")})`, ms: Math.round(settle * 1000) };
}

/** `Animations.gentle` on iOS: the app's default settle. */
export const gentle = spring(0.4, 0.15);
