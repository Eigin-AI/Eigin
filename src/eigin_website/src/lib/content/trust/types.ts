export type TrustLink = { label: string; href: string };

/** One claim, deepening from a plain summary to details and evidence. */
export type TrustClaim = {
  id: string;
  title: string;
  diagram: "device" | "models" | "actions" | "sync" | "money" | "open";
  /** Shown as a tag when the claim covers something not yet launched. */
  status?: string;
  summary: string;
  details: string[];
};

/** Text drawn inside each diagram, plus a description for screen readers. */
export type DiagramLabels = {
  motion: { pause: string; play: string };
  device: {
    description: string;
    device: string;
    memory: string;
    goals: string;
    voice: string;
    notes: string;
    conversation: string;
    local: string;
    cloud: string;
  };
  models: {
    description: string;
    device: string;
    local: string;
    relay: string;
    own: string;
    ask: string;
  };
  actions: {
    description: string;
    others: string;
    calendar: string;
    note: string;
    email: string;
    code: string;
    agent: string;
    ask: string;
  };
  sync: {
    description: string;
    device: string;
    team: string;
    message: [string, string];
    relay: string;
    relayNote: string;
  };
  money: {
    description: string;
    cloud: string;
    cloudNote: string;
    team: string;
    teamNote: string;
    refused: [string, string, string];
  };
  open: { description: string; others: string; trustUs: string; eigin: string; items: string[] };
};

export type TrustContent = {
  title: string;
  description: string;
  heading: string;
  introduction: string;
  more: string;
  claims: TrustClaim[];
  diagrams: DiagramLabels;
  limits: { title: string; introduction: string; items: { title: string; body: string }[] };
  responsible: {
    title: string;
    body: string;
    people: { name: string; role: string; photo: string }[];
  };
  transparency: { title: string; groups: { title: string; links: TrustLink[] }[] };
};
