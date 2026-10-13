import type { IconName } from "@lib";

/**
 * What iOS currently allows, as far as iOS will say.
 *
 * Apple Health reports what Eigin may save, kind by kind, but never what it
 * may read. Calendar, Reminders and Location report everything.
 */
export interface Access {
  /** Kinds iOS has turned off, as "reads/Name" or "saves/Name". */
  off: string[];
  /** Said only when the integration can't work at all: one line, then why. */
  notice?: { status: string; title: string; body: string };
}

/**
 * Something on the phone Eigin can reach once iOS allows it.
 *
 * These are integrations like any other: listed, added and removed the same
 * way. What sets them apart is that iOS owns the permission, so each one says
 * where that permission lives and shows what iOS has turned off.
 */
export interface PlatformIntegration {
  id: string;
  name: string;
  icon: IconName;
  /** What it gives the agent, for list rows. */
  summary: string;
  /** Who asks for the permission, named as the person will see it. */
  askedBy: string;
  reads: string[];
  saves: string[];
  /** Where the permission itself is changed, as the person will find it. */
  permissionIn: string;
  /** Every state iOS can report, keyed for the gallery's controls. */
  access: Record<string, Access>;
}

const allowed: Access = { off: [] };

export const platformIntegrations: PlatformIntegration[] = [
  {
    id: "health",
    name: "Apple Health",
    icon: "functional/heart",
    summary: "Activity, sleep and nutrition",
    askedBy: "Apple Health",
    reads: ["Activity", "Sleep", "Nutrition", "Body measurements", "Heart"],
    saves: ["Meals", "Sleep", "Body measurements"],
    permissionIn: "Apple Health",
    access: {
      allowed,
      partly: { off: ["saves/Body measurements"] },
      "saving off": { off: ["saves/Meals", "saves/Sleep", "saves/Body measurements"] },
    },
  },
  {
    id: "calendar",
    name: "Apple Calendar",
    icon: "brand/calendar",
    summary: "Events on this phone",
    askedBy: "iOS",
    reads: ["Events"],
    saves: ["Events"],
    permissionIn: "Settings",
    access: {
      allowed,
      /* iOS can share a calendar add-only: Eigin can write but not see. */
      partly: { off: ["reads/Events"] },
      off: {
        off: ["reads/Events", "saves/Events"],
        notice: {
          status: "Not allowed",
          title: "Calendar is off in Settings",
          body: "Allow Eigin in Settings to use your calendar here.",
        },
      },
    },
  },
  {
    id: "reminders",
    name: "Apple Reminders",
    icon: "functional/check_circle",
    summary: "Lists on this phone",
    askedBy: "iOS",
    reads: ["Reminders"],
    saves: ["Reminders"],
    permissionIn: "Settings",
    access: {
      allowed,
      off: {
        off: ["reads/Reminders", "saves/Reminders"],
        notice: {
          status: "Not allowed",
          title: "Reminders are off in Settings",
          body: "Allow Eigin in Settings to use your reminders here.",
        },
      },
    },
  },
  {
    id: "location",
    name: "Location",
    icon: "functional/location",
    summary: "Where you are, while you use Eigin",
    askedBy: "iOS",
    reads: ["Location"],
    saves: [],
    permissionIn: "Settings",
    access: {
      allowed,
      off: {
        off: ["reads/Location"],
        notice: {
          status: "Not allowed",
          title: "Location is off in Settings",
          body: "Allow Eigin in Settings to use where you are.",
        },
      },
    },
  },
];

/** Where connecting stands: told what it reads, waiting on iOS, refused, or done. */
export type ConnectPlatformStep = "disclosure" | "asking" | "refused" | "done";

export function platformIntegration(id: string): PlatformIntegration {
  return platformIntegrations.find((entry) => entry.id === id) ?? platformIntegrations[0];
}

/** Kinds of data as one phrase: "Activity, sleep and nutrition". */
export function listed(kinds: string[]): string {
  const names = kinds.map((kind, index) => (index === 0 ? kind : kind.toLowerCase()));
  return names.length < 2
    ? (names[0] ?? "")
    : `${names.slice(0, -1).join(", ")} and ${names.at(-1)}`;
}
