import type { IconName, VisualCardVariant } from "@lib";

/** Steps in the first-launch flow, in order. Mirrors `OnboardingStep`. */
export type OnboardingStep =
  "welcome" | "name" | "priority" | "inference" | "initiative" | "conversation" | "reveal";

/** Coarse avatar fill per setup step. The conversation drives the rest. */
export const avatarProgress: Record<OnboardingStep, number> = {
  welcome: 0.05,
  name: 0.18,
  priority: 0.3,
  inference: 0.4,
  initiative: 0.5,
  conversation: 0.5,
  reveal: 1,
};

export function isSetupStep(step: OnboardingStep): boolean {
  return step !== "conversation" && step !== "reveal";
}

/** What the avatar says on each setup step, personalised with the name so far. */
export function speech(step: OnboardingStep, name: string): { title: string; text: string } {
  switch (step) {
    case "welcome":
      return {
        title: "Hi there.",
        text: "I’m Eigin, your personal AI.\n\nI live on your device, I answer to you, and no one else is listening.\n\nBefore we begin, I’d like to get to know you.",
      };
    case "name":
      return { title: "First things first.", text: "What should I call you?" };
    case "priority":
      return {
        title: name ? `Nice to meet you, ${name}.` : "Nice to meet you.",
        text: "What are you hoping to do with your personal AI?\n\nI can shape myself around that.",
      };
    case "inference":
      return {
        title: "Now, let’s give me a brain.",
        text: "I can think with powerful AI in the cloud, hosted in Europe.\n\nOr I can run on your device. You can change this anytime.",
      };
    case "initiative":
      return {
        title: "One more thing.",
        text: "I can keep working when you’re away, and reach out when something’s worth your attention.\n\nOr I can stay quiet and only help when you ask. Your call.",
      };
    default:
      return { title: "", text: "" };
  }
}

/** The priority cards. Mirrors `OnboardingPriority`. */
export const priorities: {
  title: string;
  explainer: string;
  symbol: IconName;
  variant: VisualCardVariant;
}[] = [
  {
    title: "Stay on top of life",
    explainer: "Your schedule, the day ahead, and the small stuff that piles up.",
    symbol: "illustration/tree",
    variant: "brand",
  },
  {
    title: "Keep in touch",
    explainer: "The people who matter to you and what’s going on in their lives.",
    symbol: "illustration/person-2",
    variant: "warm",
  },
  {
    title: "Think out loud",
    explainer: "Talk something out, weigh a decision, clear your head.",
    symbol: "illustration/ghost",
    variant: "soft",
  },
  {
    title: "Something else",
    explainer: "Not quite any of these? We’ll figure it out as we talk.",
    symbol: "illustration/bird",
    variant: "neutral",
  },
];
