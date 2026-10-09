/* A made-up conversation for the chat builder: plain data, so it travels in a
   shot's URL and lives in shots.ts like any other setting. */

import type { IconName } from "../../lib/generated/icons";

export type TurnKind = "user" | "agent" | "tools" | "options";

/**
 * One block in the feed. Every kind is one text: a message, the agent's
 * markdown, or one line per tool call or option card, written as
 * `Name | detail`. An option card can add `| category` to pick its illustration.
 */
export interface Turn {
  kind: TurnKind;
  text: string;
}

export const turnKinds: { id: TurnKind; label: string; hint: string }[] = [
  { id: "user", label: "You", hint: "What you ask" },
  { id: "agent", label: "Eigin", hint: "The reply, in markdown" },
  { id: "tools", label: "Tools", hint: "One per line: Search notes | 3 matches" },
  { id: "options", label: "Options", hint: "One per line: Label | description | care" },
];

/** A `Name | detail` line, split at the first pipe. */
export function splitLine(line: string): { name: string; detail: string } {
  const [name, ...rest] = line.split("|");
  return { name: name.trim(), detail: rest.join("|").trim() };
}

/* The categories the agent tags options with, and the illustration each draws,
   as the app maps them in `AgentOptions.swift`. */
export const optionCategories: Record<string, IconName> = {
  focus: "illustration/circle",
  explore: "illustration/bird",
  create: "illustration/ink-1",
  organise: "illustration/tree",
  care: "illustration/flower",
  connect: "illustration/person-2",
  decide: "illustration/volcano",
  move: "illustration/wave",
  grow: "illustration/root",
  play: "illustration/butterfly",
  reflect: "illustration/ghost",
  prepare: "illustration/mountain",
  celebrate: "illustration/ink-2",
  learn: "illustration/cell",
  build: "illustration/crab",
  rest: "illustration/moon",
  challenge: "illustration/octopus",
  share: "illustration/person-1",
  discover: "illustration/ghost",
  express: "illustration/cactus",
};

/** A `Label | description | category` line; the category is optional. */
export function splitOption(line: string): {
  label: string;
  description: string;
  symbol?: IconName;
} {
  const [label, description = "", category = ""] = line.split("|").map((part) => part.trim());
  return { label, description, symbol: optionCategories[category.toLowerCase()] };
}

export function lines(text: string): string[] {
  return text
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean);
}
