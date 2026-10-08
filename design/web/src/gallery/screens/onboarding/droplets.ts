import { RELEASE } from "@gallery/screens/onboarding/hatch";

/**
 * The droplets around the release. Through the last breath they fall in from
 * beyond the screen, faster and faster, and the blob swallows each one: the
 * agent gathering itself. On the release a crown of them splashes off.
 */

export interface Droplet {
  x: number;
  y: number;
  /** Half-length along the way it travels, and half-width across it. */
  long: number;
  wide: number;
  /** The way it travels, in degrees. */
  rotate: number;
  opacity: number;
  /** How much of the brand colour it has taken on, 0–1. */
  tint: number;
}

/** A seeded random, so the droplets fall the same way every time. */
function seeded(seed: number): () => number {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let x = Math.imul(seed ^ (seed >>> 15), seed | 1);
    x ^= x + Math.imul(x ^ (x >>> 7), x | 61);
    return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
  };
}

const clamp = (value: number) => Math.min(Math.max(value, 0), 1);
const easeOut = (value: number) => 1 - (1 - value) ** 3;
const degrees = (radians: number) => (radians * 180) / Math.PI;

const random = seeded(0xd209);

/** The droplets falling in, in units of the blob's radius. */
const falling = Array.from({ length: 16 }, (_, i) => {
  // More and more of them, the closer the release: the last lands just before it.
  const lands = RELEASE - 0.04 - 1.15 * ((i + random() * 0.6) / 16) ** 1.6;
  const travel = 0.7 + 0.25 * random();
  return {
    lands,
    starts: lands - travel,
    travel,
    from: 0.85 + 0.15 * random(),
    angle: i * 2.39996 + random() * 0.4,
    curl: (random() < 0.5 ? -1 : 1) * (0.3 + 0.3 * random()),
    size: 0.05 + 0.08 * random(),
  };
});

/** The crown thrown off on the release. */
const thrown = Array.from({ length: 9 }, (_, i) => ({
  angle: (i / 9) * 2 * Math.PI + random() * 0.5,
  life: 0.4 + 0.15 * random(),
  reach: 1.5 + 0.6 * random(),
  size: 0.05 + 0.05 * random(),
}));

/**
 * The droplets falling in at `t`, in pixels from the blob's centre. They set
 * off `reach` pixels out, past the edge of the screen.
 */
export function gathering(t: number, radius: number, reach: number): Droplet[] {
  return falling.flatMap((drop) => {
    const p = (t - drop.starts) / drop.travel;
    if (p <= 0 || p >= 1) return [];
    const from = reach * drop.from;
    // Falls in like into a well: slow far out, fastest as it lands.
    const distance = radius + (from - radius) * (1 - p ** 2.4);
    const speed = ((from - radius) * 2.4 * p ** 1.4) / drop.travel;
    const angle = drop.angle + drop.curl * (1 - p) ** 2;
    const stretch = 1 + Math.min(2.5, speed / 900);
    const size = radius * drop.size * (1 - 0.4 * clamp((p - 0.9) / 0.1));
    return [
      {
        x: distance * Math.cos(angle),
        y: distance * Math.sin(angle),
        long: size * stretch,
        wide: size / Math.sqrt(stretch),
        rotate: degrees(angle),
        opacity: clamp(p / 0.15),
        // Muted out in the world, the brand colour by the time it lands.
        tint: p ** 1.5,
      },
    ];
  });
}

/**
 * How far the blob's edge at `angle` reaches out to swallow droplets: it necks
 * out to meet each one as it lands, then draws it in. In units of its radius.
 */
export function swallowing(t: number, angle: number): number {
  return falling.reduce((sum, drop) => {
    const since = t - drop.lands;
    if (since < -0.08 || since > 0.4) return sum;
    const envelope = since < 0 ? 1 + since / 0.08 : Math.exp(-since / 0.1);
    const away = Math.atan2(Math.sin(angle - drop.angle), Math.cos(angle - drop.angle));
    return sum + 1.6 * drop.size * envelope * Math.exp(-((away / 0.32) ** 2));
  }, 0);
}

/** The crown splashing off the blob on the release, in pixels from its centre. */
export function splash(t: number, radius: number): Droplet[] {
  return thrown.flatMap((drop) => {
    const p = (t - RELEASE - 0.02) / drop.life;
    if (p <= 0 || p >= 1) return [];
    const distance = radius * (0.95 + (drop.reach - 0.95) * easeOut(p));
    const stretch = 1 + 1.8 * (1 - p) ** 2;
    const size = radius * drop.size * (1 - p) ** 0.8;
    return [
      {
        x: distance * Math.cos(drop.angle),
        y: distance * Math.sin(drop.angle),
        long: size * stretch,
        wide: size / Math.sqrt(stretch),
        rotate: degrees(drop.angle),
        opacity: clamp((1 - p) / 0.3),
        tint: 1,
      },
    ];
  });
}
