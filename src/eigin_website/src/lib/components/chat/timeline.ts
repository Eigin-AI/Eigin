import { springCurve } from "@eigin/ui";
import type { ChatExample } from "../../content/home/types";

const rise = springCurve(0.45, 0.2);
const glide = springCurve(0.4, 0.15);
const clamp = (value: number) => Math.max(0, Math.min(1, value));
const reveal = (elapsed: number, start: number, duration = 150) => {
  const t = clamp((elapsed - start) / duration);
  return t * t * (3 - 2 * t);
};

/** Each reveal waits for the preceding movement to settle. Times are milliseconds. */
export function timeline(example: ChatExample) {
  const lift = 650;
  const compose = lift + 700;
  const typeStart = compose + 200;
  const send = typeStart + example.ask.length * 30 + 1500;
  const move = send + 200;
  const ask = move + 650;
  const reply = ask + 700;
  const ending = reply + words(example.reply).length * 65 + 250;
  const leave = ending + Math.max(4500, words(example.reply).length * 160) + 2000;
  const home = leave + 150;
  return {
    lift,
    compose,
    typeStart,
    send,
    move,
    ask,
    reply,
    ending,
    leave,
    home,
    end: home + 500,
  };
}

type Timeline = ReturnType<typeof timeline>;

/** The visual state is sampled from one clock, so pausing freezes its choreography. */
export function frame(example: ChatExample, line: Timeline, elapsed: number) {
  const clearing = reveal(elapsed, line.leave);
  return {
    phase:
      elapsed >= line.home
        ? "returning"
        : elapsed >= line.leave
          ? "leaving"
          : elapsed >= line.reply
            ? "reply"
            : elapsed >= line.ask
              ? "thinking"
              : elapsed >= line.move
                ? "moving"
                : elapsed >= line.send
                  ? "sending"
                  : elapsed >= line.compose
                    ? "compose"
                    : elapsed >= line.lift
                      ? "rising"
                      : "intro",
    wobbling:
      elapsed < line.lift - 400 ||
      (elapsed >= line.compose && elapsed < line.send - 400) ||
      (elapsed >= line.ask && elapsed < line.leave - 400),
    said: words(example.reply)
      .slice(0, Math.max(0, Math.floor((elapsed - line.reply) / 65)))
      .join(""),
    draft: example.ask.slice(0, Math.max(0, Math.floor((elapsed - line.typeStart) / 30))),
    composer: reveal(elapsed, line.compose) * (1 - reveal(elapsed, line.send)),
    tool: reveal(elapsed, line.ask) * (1 - clearing),
    question: reveal(elapsed, line.ask) * (1 - clearing),
    answer: reveal(elapsed, line.reply) * (1 - clearing),
    ending: reveal(elapsed, line.ending) * (1 - clearing),
  };
}

/** Onboarding-like squash before take-off and stretch along the direction of travel. */
export function blobPose(
  line: Timeline,
  elapsed: number,
  width: number,
  height: number,
  answerY: number,
  answerX = 36,
) {
  const center = { x: width / 2, y: height / 2, scale: 1 };
  const above = { x: width / 2, y: height * 0.25, scale: 0.48 };
  const beside = { x: answerX, y: answerY, scale: 0.28 };
  let from = center;
  let to = above;
  let time = (elapsed - line.lift) / 1000;
  let curve = rise;
  let stretchX = 1;
  let stretchY = 1;
  if (elapsed < line.lift) {
    const crouch = Math.sin((reveal(elapsed, line.lift - 300, 300) * Math.PI) / 2);
    return { ...center, stretchX: 1 + crouch * 0.1, stretchY: 1 - crouch * 0.09 };
  }
  if (elapsed >= line.home) {
    return homePose({ ...beside, stretchX: 1, stretchY: 1 }, elapsed - line.home, width, height);
  } else if (elapsed >= line.move) {
    from = above;
    to = beside;
    time = (elapsed - line.move) / 1000;
    curve = glide;
  }
  const progress = time >= 0.7 ? 1 : curve(time);
  const speed = Math.max(0, (curve(time + 0.004) - curve(time - 0.004)) / 0.008);
  const stretch = Math.min(0.18, speed * 0.035);
  if (from.x === to.x) {
    stretchY += stretch;
    stretchX -= stretch * 0.6;
  } else {
    stretchX += stretch;
    stretchY -= stretch * 0.6;
  }
  return {
    x: from.x + (to.x - from.x) * progress,
    y: from.y + (to.y - from.y) * progress,
    scale: from.scale + (to.scale - from.scale) * progress,
    stretchX,
    stretchY,
  };
}

/** The same spring returns the blob home after automatic and selected case changes. */
export function homePose(
  from: { x: number; y: number; scale: number; stretchX: number; stretchY: number },
  elapsed: number,
  width: number,
  height: number,
) {
  if (elapsed <= 0) return from;
  const time = (elapsed / 1000) * 1.4;
  const progress = time >= 0.7 ? 1 : rise(time);
  return {
    x: from.x + (width / 2 - from.x) * progress,
    y: from.y + (height / 2 - from.y) * progress,
    scale: from.scale + (1 - from.scale) * progress,
    stretchX: from.stretchX + (1 - from.stretchX) * progress,
    stretchY: from.stretchY + (1 - from.stretchY) * progress,
  };
}

/** Preserve spaces while revealing complete words in a stable text layout. */
export function words(text: string): string[] {
  return text.match(/\S+\s*/g) ?? [];
}
