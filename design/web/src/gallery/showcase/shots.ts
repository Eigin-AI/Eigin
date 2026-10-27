import { colorTokens } from "../../lib/generated/tokens";
import type { Turn } from "./conversation";

/* Plain data with relative imports only, so `just showcase` can load it in
   Node without the gallery's components or aliases. */

export type Layout = "tilt" | "flat";
export type Platform = "ios";

/** How far the device turns, in degrees. */
export interface Tilt {
  yaw: number;
  pitch: number;
  roll: number;
}

/** Where the headline sits: a fixed spot on the canvas, whatever the phone does. */
export type Anchor =
  | "top-left"
  | "top-center"
  | "top-right"
  | "center-left"
  | "center-right"
  | "bottom-left"
  | "bottom-right";

export const anchors: { id: Anchor; label: string }[] = [
  { id: "center-left", label: "Centre left" },
  { id: "center-right", label: "Centre right" },
  { id: "top-left", label: "Top left" },
  { id: "top-center", label: "Top centre" },
  { id: "top-right", label: "Top right" },
  { id: "bottom-left", label: "Bottom left" },
  { id: "bottom-right", label: "Bottom right" },
];

export type HeadlineSize = "s" | "m" | "l" | "xl";

/** Headline sizes, as multiples of the size each canvas starts from. */
export const headlineSizes: { id: HeadlineSize; label: string; scale: number }[] = [
  { id: "s", label: "S", scale: 0.75 },
  { id: "m", label: "M", scale: 1 },
  { id: "l", label: "L", scale: 1.25 },
  { id: "xl", label: "XL", scale: 1.5 },
];

export function headlineScale(shot: Shot): number {
  return headlineSizes.find((size) => size.id === shot.headlineSize)?.scale ?? 1;
}

/** The side the headline holds, which the phone leaves free by default. */
export function headlineSide(shot: Shot): "left" | "center" | "right" {
  if (!shot.headline) return "center";
  return shot.headlineAt.endsWith("left")
    ? "left"
    : shot.headlineAt.endsWith("right")
      ? "right"
      : "center";
}

/** Where the softbox hangs, so the light can be set after the phone is posed. */
export interface Light {
  /** Around the phone, in degrees: 0 is straight above, negative to the left. */
  angle: number;
  /** Up from the screen's plane toward the camera, in degrees. */
  height: number;
}

/** Where the phone sits, on top of where its layout puts it. */
export interface Placement {
  /** Offsets as a percentage of the canvas width and height. */
  x: number;
  y: number;
  /** Multiplies the phone's size. */
  scale: number;
}

/** Everything that decides what a shot looks like. The URL carries it whole. */
export interface Shot {
  /** A gallery screen id from `screenEntries`, or `conversation`. */
  screen: string;
  layout: Layout;
  background: string;
  scheme: "light" | "dark";
  size: string;
  headline: string;
  headlineAt: Anchor;
  headlineSize: HeadlineSize;
  tilt: Tilt;
  placement: Placement;
  /** Studio light on the glass, from 0 (none) to 1. */
  glare: number;
  light: Light;
  /** How far down the screen is scrolled, 0 to 100%; unset leaves the screen's own default. */
  scroll?: number;
  /** What the chat builder draws, when `screen` is `conversation`. */
  conversation?: Turn[];
}

/** The screen id that draws a shot's own conversation. */
export const conversationScreen = "conversation";

/** A shot worth keeping: it renders to `design/assets/showcase/<platform>/<id>.jpg`. */
export interface ShotEntry extends Shot {
  id: string;
  title: string;
  platform: Platform;
}

export interface Size {
  id: string;
  label: string;
  width: number;
  height: number;
}

export const sizes: Size[] = [
  { id: "16x9", label: "16:9", width: 1920, height: 1080 },
  { id: "4x5", label: "4:5", width: 1080, height: 1350 },
  { id: "1x1", label: "1:1", width: 1080, height: 1080 },
];

export interface Background {
  id: string;
  label: string;
  fill: string;
  /** Headline color that reads on the fill. */
  ink: string;
}

function token(name: string, mode: "light" | "dark" = "light"): string {
  const found = colorTokens.find((candidate) => candidate.name === name);
  if (!found) throw new Error(`Unknown color token: ${name}`);
  return found[mode];
}

/* Brand surfaces only, the same set the option cards use, so a shot always
   looks like Eigin. Flat fills: the phone and its shadow carry the depth. */
const darkInk = token("text.standard.base");
const lightInk = token("text.standard.base", "dark");

export const backgrounds: Background[] = [
  { id: "impact", label: "Impact", fill: token("surface.impact.base"), ink: darkInk },
  { id: "deep", label: "Deep", fill: token("surface.impact.elevated"), ink: lightInk },
  { id: "active", label: "Active", fill: token("interaction.active.fill"), ink: lightInk },
  { id: "warm", label: "Warm", fill: token("surface.impact.alternative"), ink: darkInk },
  { id: "soft", label: "Soft", fill: token("surface.impact.subtle"), ink: darkInk },
  { id: "light", label: "Light", fill: token("surface.standard.elevated"), ink: darkInk },
  { id: "dark", label: "Dark", fill: token("surface.standard.base", "dark"), ink: lightInk },
  { id: "transparent", label: "None", fill: "transparent", ink: darkInk },
];
export const layouts: { id: Layout; label: string }[] = [
  { id: "tilt", label: "Tilt" },
  { id: "flat", label: "Flat" },
];

/** Every shot `just showcase` renders. Copy stays fictional, per App Store rules. */
export const shotEntries: ShotEntry[] = [
  {
    id: "hero",
    title: "Hero",
    platform: "ios",
    screen: "chat",
    layout: "tilt",
    background: "deep",
    scheme: "light",
    size: "16x9",
    headline: "Personal AI that's truly yours.",
    headlineAt: "center-left",
    headlineSize: "m",
    tilt: { yaw: -24, pitch: 10, roll: 6 },
    placement: { x: 0, y: 0, scale: 1 },
    glare: 0.15,
    light: { angle: -40, height: 35 },
  },
  {
    id: "chat-builder",
    title: "Chat builder",
    platform: "ios",
    screen: conversationScreen,
    layout: "tilt",
    background: "warm",
    scheme: "light",
    size: "16x9",
    headline: "Plans that\nfit your week.",
    headlineAt: "center-left",
    headlineSize: "m",
    tilt: { yaw: -24, pitch: 10, roll: 6 },
    placement: { x: 0, y: 0, scale: 1 },
    glare: 0.15,
    light: { angle: -40, height: 35 },
    conversation: [
      { kind: "user", text: "Can you plan a slow Saturday in Lisbon? I land Friday night." },
      { kind: "tools", text: "Check weather | Sunny, 24°\nSearch notes | lisbon-ideas.md" },
      {
        kind: "agent",
        text: "Sunny all day, so here's an easy one from your notes:\n\n- **Morning:** coffee in Príncipe Real, then wander down to Alfama.\n- **Afternoon:** lunch by the river and a long sit at the Gulbenkian garden.\n- **Evening:** sunset at the Graça viewpoint.\n\nWant me to keep it this loose?",
      },
      {
        kind: "options",
        text: "Keep it loose | Nothing booked, just the outline\nBook dinner | A table near Graça for eight\nSlower still | Drop the evening plans",
      },
    ],
  },
  // The README and docs hero: something the app does today, left to run on its own.
  {
    id: "get-eigin",
    title: "Get Eigin",
    platform: "ios",
    screen: conversationScreen,
    layout: "tilt",
    background: "impact",
    scheme: "light",
    size: "16x9",
    headline: "Get your hands on a hands off AI.",
    headlineAt: "center-left",
    headlineSize: "l",
    tilt: { yaw: -24, pitch: 10, roll: 6 },
    placement: { x: 4, y: 0, scale: 1 },
    glare: 0.15,
    light: { angle: -40, height: 35 },
    scroll: 0,
    conversation: [
      { kind: "user", text: "Keep an eye on school emails for me?" },
      {
        kind: "agent",
        text: "OK, I'll keep an eye on it. For now, there's a **trip form** and Thursday's **bake sale**. What should we tackle first?",
      },
      {
        kind: "options",
        text: "Fill in the form | I'll draft it for you to check. | create\nRemind me Thursday | For the bake sale | focus",
      },
    ],
  },
  // The website's "Get Eigin" section: the same moment, unframed, for a dark page.
  {
    id: "website-get",
    title: "Website: Get Eigin",
    platform: "ios",
    screen: conversationScreen,
    layout: "tilt",
    background: "transparent",
    scheme: "light",
    size: "1x1",
    headline: "",
    headlineAt: "center-left",
    headlineSize: "l",
    tilt: { yaw: -24, pitch: 10, roll: 6 },
    placement: { x: 0, y: -1.5, scale: 1.33 },
    glare: 0.15,
    light: { angle: -40, height: 35 },
    scroll: 0,
    conversation: [
      { kind: "user", text: "Keep an eye on school emails for me?" },
      {
        kind: "agent",
        text: "OK, I'll keep an eye on it. For now, there's a **trip form** and Thursday's **bake sale**. What should we tackle first?",
      },
      {
        kind: "options",
        text: "Fill in the form | I'll draft it for you to check. | create\nRemind me Thursday | For the bake sale | focus",
      },
    ],
  },
];

export function sizeOf(shot: Shot): Size {
  return sizes.find((size) => size.id === shot.size) ?? sizes[0];
}

export function backgroundOf(shot: Shot): Background {
  return backgrounds.find((background) => background.id === shot.background) ?? backgrounds[0];
}

export type Format = "jpg" | "png";

/** Where a shot's export lands, relative to `design/assets/showcase`. JPEG is what the repo keeps. */
export function assetPath(entry: ShotEntry, format: Format = "jpg"): string {
  return `${entry.platform}/${entry.id}.${format}`;
}
