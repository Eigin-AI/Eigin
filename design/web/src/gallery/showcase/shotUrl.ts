import { anchors, headlineSizes, type Layout, type Shot } from "./shots";

/* A shot travels as a hash query, so a gallery URL is enough to render it
   again — in the browser, from the export button, or from `just showcase`. */

/** The query for whatever differs from `base`. */
export function encodeShot(shot: Shot, base: Shot): URLSearchParams {
  const params = new URLSearchParams();
  const set = (key: string, value: string | number, baseValue: string | number) => {
    if (value !== baseValue) params.set(key, String(value));
  };
  set("screen", shot.screen, base.screen);
  set("layout", shot.layout, base.layout);
  set("bg", shot.background, base.background);
  set("scheme", shot.scheme, base.scheme);
  set("size", shot.size, base.size);
  set("headline", shot.headline, base.headline);
  set("at", shot.headlineAt, base.headlineAt);
  set("type", shot.headlineSize, base.headlineSize);
  set("yaw", shot.tilt.yaw, base.tilt.yaw);
  set("pitch", shot.tilt.pitch, base.tilt.pitch);
  set("roll", shot.tilt.roll, base.tilt.roll);
  set("x", shot.placement.x, base.placement.x);
  set("y", shot.placement.y, base.placement.y);
  set("scale", shot.placement.scale, base.placement.scale);
  set("glare", shot.glare, base.glare);
  set("la", shot.light.angle, base.light.angle);
  set("lh", shot.light.height, base.light.height);
  if (shot.scroll !== undefined) set("scroll", shot.scroll, base.scroll ?? -1);
  if (shot.conversation) {
    set("chat", JSON.stringify(shot.conversation), JSON.stringify(base.conversation));
  }
  return params;
}

/** `base` with whatever the query overrides. */
export function decodeShot(params: URLSearchParams, base: Shot): Shot {
  const conversation = (): Shot["conversation"] => {
    try {
      return params.has("chat") ? JSON.parse(params.get("chat")!) : base.conversation;
    } catch {
      return base.conversation;
    }
  };
  const number = (key: string, fallback: number) => {
    const value = Number(params.get(key));
    return params.has(key) && Number.isFinite(value) ? value : fallback;
  };
  return {
    screen: params.get("screen") ?? base.screen,
    layout: (params.get("layout") as Layout | null) ?? base.layout,
    background: params.get("bg") ?? base.background,
    scheme: params.get("scheme") === "dark" ? "dark" : params.has("scheme") ? "light" : base.scheme,
    size: params.get("size") ?? base.size,
    headline: params.get("headline") ?? base.headline,
    headlineAt: anchors.find((anchor) => anchor.id === params.get("at"))?.id ?? base.headlineAt,
    headlineSize:
      headlineSizes.find((size) => size.id === params.get("type"))?.id ?? base.headlineSize,
    tilt: {
      yaw: number("yaw", base.tilt.yaw),
      pitch: number("pitch", base.tilt.pitch),
      roll: number("roll", base.tilt.roll),
    },
    placement: {
      x: number("x", base.placement.x),
      y: number("y", base.placement.y),
      scale: number("scale", base.placement.scale),
    },
    glare: number("glare", base.glare),
    light: {
      angle: number("la", base.light.angle),
      height: number("lh", base.light.height),
    },
    scroll: params.has("scroll") ? Math.min(100, Math.max(0, number("scroll", 0))) : base.scroll,
    conversation: conversation(),
  };
}

/** The hash that draws a shot alone at its pixel size, sampled `time` seconds in. */
export function renderHash(id: string, shot: Shot, base: Shot, time = 0): string {
  const params = encodeShot(shot, base);
  params.set("render", "");
  if (time) params.set("t", String(time));
  return `#/showcase/${id}?${params}`;
}
