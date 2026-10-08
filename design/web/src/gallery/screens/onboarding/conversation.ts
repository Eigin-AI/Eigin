import type { ToolCall } from "@lib";

/** One agent turn of the scripted onboarding conversation. */
export interface Turn {
  /** What the agent says. */
  reply: string;
  /** Tools the agent ran before replying. */
  tools?: ToolCall[];
  /** Avatar fill once this turn lands, as the side-channel assessment would set it. */
  fill: number;
  /** What the user says back, waiting in the composer. */
  suggestion?: string;
  /** The agent called `done`: onboarding seals and the reveal begins. */
  done?: boolean;
}

/**
 * A plausible onboarding conversation. In the app every word of the agent's
 * side is generated; this stands in so the flow can be walked end to end.
 */
export function script(name: string, priority: string): Turn[] {
  return [
    {
      reply: `Good to properly meet you, ${name}. Thanks for walking through all that with me.\n\nI’d like to get to know you a little, so I can set myself up just right. You picked **${priority.toLowerCase()}**. What does a normal week look like for you right now?`,
      fill: 0.55,
      suggestion:
        "Busy. Work is mostly meetings, and I keep forgetting the small personal stuff, like birthdays and appointments.",
    },
    {
      reply:
        "That’s a common squeeze: the work calendar is loud, so the personal things get drowned out.\n\nWhen something is about to slip, how would you like me to step in? A nudge the day before, or a short rundown each morning?",
      tools: [{ id: "core-1", name: "Edit Core", status: "completed", result: "user.md" }],
      fill: 0.72,
      suggestion: "A short morning rundown would be great. Keep it brief.",
    },
    {
      reply:
        "Brief morning rundowns it is.\n\nOne last thing before I set myself up: I’d like a name of my own. I’m thinking **Ford**, with 🛰️ as my face. Steady, quietly keeping track of things in orbit. Does that suit you?",
      tools: [
        { id: "core-2", name: "Edit Core", status: "completed", result: "soul.md" },
        { id: "presentation", name: "Set Presentation", status: "completed", result: "Ford 🛰️" },
      ],
      fill: 0.9,
      suggestion: "Love it.",
    },
    {
      reply: "Then it’s settled. Give me a moment to put myself together.",
      fill: 1,
      done: true,
    },
  ];
}
