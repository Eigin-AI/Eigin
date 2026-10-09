import type { Light, Tilt } from "./shots";

/* The screen is a mirror lit by one softbox. Where that softbox shows up on
   the glass depends on how the phone is turned, so the glare is worked out
   from the same rotation the phone is drawn with, in CSS space (x right,
   y down, z toward the camera). */

type Vec = [number, number, number];

const dot = (a: Vec, b: Vec) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const scale = (a: Vec, k: number): Vec => [a[0] * k, a[1] * k, a[2] * k];
const sub = (a: Vec, b: Vec): Vec => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
const normalize = (a: Vec) => scale(a, 1 / Math.hypot(...a));

/** Toward the softbox, from its angle around the phone and its height. */
function toward({ angle, height }: Light): Vec {
  const [a, h] = [angle, height].map((deg) => (deg * Math.PI) / 180);
  return normalize([Math.cos(h) * Math.sin(a), -Math.cos(h) * Math.cos(a), Math.sin(h)]);
}

type Mat = [Vec, Vec, Vec];

const multiply = (a: Mat, b: Mat): Mat =>
  a.map((row) => [0, 1, 2].map((col) => dot(row, [b[0][col], b[1][col], b[2][col]]))) as Mat;

const apply = (m: Mat, v: Vec): Vec => [dot(m[0], v), dot(m[1], v), dot(m[2], v)];
const transpose = (m: Mat): Mat => [0, 1, 2].map((i) => [m[0][i], m[1][i], m[2][i]]) as Mat;

/** `rotateX(pitch) rotateY(yaw) rotateZ(roll)`, as CSS composes it. */
function rotation({ yaw, pitch, roll }: Tilt): Mat {
  const [x, y, z] = [pitch, yaw, roll].map((deg) => (deg * Math.PI) / 180);
  const rx: Mat = [
    [1, 0, 0],
    [0, Math.cos(x), -Math.sin(x)],
    [0, Math.sin(x), Math.cos(x)],
  ];
  const ry: Mat = [
    [Math.cos(y), 0, Math.sin(y)],
    [0, 1, 0],
    [-Math.sin(y), 0, Math.cos(y)],
  ];
  const rz: Mat = [
    [Math.cos(z), -Math.sin(z), 0],
    [Math.sin(z), Math.cos(z), 0],
    [0, 0, 1],
  ];
  return multiply(multiply(rx, ry), rz);
}

/** Where the softbox reflects on the screen, and how brightly. */
export interface Glare {
  /** The reflection's centre, as a percentage of the screen's width and height. */
  x: number;
  y: number;
  /** 0 to 1: how squarely the glass catches the light. */
  strength: number;
}

/**
 * Finds the point on the glass that mirrors the softbox into the camera.
 *
 * @param perspective the camera's distance from the screen, in screen pixels
 */
export function glareFor(
  tilt: Tilt,
  softbox: Light,
  screen: { width: number; height: number },
  perspective: number,
): Glare {
  const light = toward(softbox);
  const turn = rotation(tilt);
  const normal = apply(turn, [0, 0, 1]);
  const camera: Vec = [0, 0, perspective];

  // A ray from the camera that leaves the mirror toward the light arrives
  // along the light reflected about the normal.
  const reflected = sub(scale(normal, 2 * dot(normal, light)), light);
  const facing = dot(normal, reflected);
  if (facing <= 0) return { x: 50, y: -150, strength: 0 };
  const along = dot(normal, camera) / facing;
  const hit = sub(camera, scale(reflected, along));
  const [u, v] = apply(transpose(turn), hit);

  // Brightest when the glass faces halfway between light and camera.
  const halfway = normalize([light[0], light[1], light[2] + 1]);
  const strength = Math.max(0, dot(normal, halfway)) ** 6;

  return {
    x: 50 + (u / screen.width) * 100,
    y: 50 + (v / screen.height) * 100,
    strength,
  };
}
