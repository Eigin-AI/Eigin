import type { TrustContent } from "./types";
import daniel from "../../assets/team/daniel-rothmann.jpg";
import therkel from "../../assets/team/therkel-sand-therkelsen.jpg";

const docs = "https://code.eigin.ai/dev/eigin/-/blob/main/docs/src";

const content: TrustContent = {
  title: "Trust — Eigin",
  description:
    "How Eigin keeps personal AI private and safe, in plain language, with the evidence to check it.",
  heading: "Why trust Eigin?",
  introduction:
    "Here's how Eigin handles your data, what it can do, and where to check each claim yourself.",
  more: "How it works",
  claims: [
    {
      id: "data",
      diagram: "device",
      title: "Your data",
      summary: "Your conversations and your agent's memory are stored on your device, not with us.",
      details: [
        "Chats, memory, goals and settings are stored on your device. Cloud requests can include relevant memories and connected data.",
        "Your voice is processed on your device and never leaves it.",
        "Connected accounts are reached from your device, not through us.",
      ],
    },
    {
      id: "models",
      diagram: "models",
      title: "AI models",
      summary:
        "Your messages only go to the AI model you choose, and only after you've allowed it.",
      details: [
        "Eigin asks before anything goes to a cloud model for the first time.",
        "Our cloud AI keeps nothing and needs no account.",
        "Local inference runs on your device. Separately permitted tools can still contact connected services.",
      ],
    },
    {
      id: "actions",
      diagram: "actions",
      title: "What it can do",
      summary:
        "It can only use the tools you give it, and it asks before it changes or sends anything.",
      details: [
        "It has no computer of its own, so it can't write or run its own code.",
        "Each tool has permissions that you control.",
        "Anything risky asks you first, by default.",
      ],
    },
    {
      id: "sync",
      diagram: "sync",
      title: "Sync",
      status: "Coming soon",
      summary: "When Eigin syncs, only you and the people you share with can read it.",
      details: [
        "Sync between your devices and your team is end-to-end encrypted.",
        "Only you and the people you share with hold the keys.",
        "We pass your data along, but we can't read it.",
      ],
    },
    {
      id: "money",
      diagram: "money",
      title: "How we make money",
      summary: "We earn our keep with private cloud AI and commercial plans, not with your data.",
      details: [
        "There are no ads or tracking in the app.",
        "Our cloud service doesn't need to know who you are.",
        "We sell optional services and commercial plans, not data.",
      ],
    },
    {
      id: "open",
      diagram: "open",
      title: "Open source",
      summary:
        "Eigin is open source, so you can see how it handles your data and what it's allowed to do.",
      details: [
        "The code is public under the AGPL licence.",
        "Without us, it keeps working with a local model or your own key.",
        "You can self-host our cloud services, too.",
      ],
    },
  ],
  diagrams: {
    motion: { pause: "Pause illustration", play: "Play illustration" },
    device: {
      description:
        "Your agent stores chats, memory, goals and notes on your device. Cloud requests can include your conversation, relevant memories and permitted connected data. Local inference stays on the device; separately permitted network tools can still contact connected services.",
      device: "your device",
      memory: "Memory",
      goals: "Goals",
      voice: "Voice",
      notes: "Notes",
      conversation: "Request context",
      local: "local model",
      cloud: "cloud model",
    },
    models: {
      description:
        "Your agent runs on your device. It can use a local model inside the device, or, outside it, Eigin Relay or your own provider. Nothing goes out until you say yes.",
      device: "your device",
      local: "local model",
      relay: "eigin relay",
      own: "own provider",
      ask: "ask",
    },
    actions: {
      description:
        "It moves between two pictures. First, another agent, shown as a plain circle in a sandbox: its options multiply inside a locked-down machine until one finds the single gap and breaks out. Then your Eigin agent, with no box and a fixed set of actions: it can check your calendar and read a note, sending an email asks you first, and running code is blocked.",
      others: "other agents",
      calendar: "Check your calendar",
      note: "Read a note",
      email: "Send an email",
      code: "Run code",
      agent: "your agent",
      ask: "ask",
    },
    sync: {
      description:
        "A note on your device travels locked through Eigin Relay to your team. Only your device and your team hold keys; Eigin Relay can't open it.",
      device: "your device",
      team: "your team",
      message: ["Plans for", "Friday?"],
      relay: "Eigin Relay",
      relayNote: "Can't open it.",
    },
    money: {
      description:
        "Eigin is paid for by people who choose its cloud AI, pay as you go, and by teams on one flat price. Nothing goes to advertisers, trackers or data brokers.",
      cloud: "cloud ai",
      cloudNote: "Pay as you go.",
      team: "team plans",
      teamNote: "One flat price.",
      refused: ["Advertisers", "Trackers", "Data brokers"],
    },
    open: {
      description:
        "A closed app is a black box. Eigin is open source under the AGPL: how it stores, syncs and shares your data is all there to read.",
      others: "other apps",
      trustUs: "“Trust us.”",
      eigin: "Eigin, open source",
      items: [
        "How it stores your data",
        "How it syncs",
        "What it's allowed to do",
        "Where it sends things",
        "Everything else",
      ],
    },
  },
  limits: {
    title: "What Eigin can't do",
    introduction: "No system protects against everything. Here's where the limits are.",
    items: [
      {
        title: "Cloud models read your current conversation",
        body: "To answer you, a cloud model has to read what you send. Our cloud AI models never store your conversations, but with your own provider, its terms apply.",
      },
      {
        title: "Your device is the vault",
        body: "Your data is as safe as your device. Anyone who can open your device can read your chats.",
      },
      {
        title: "Content can try to trick the agent",
        body: "Web pages and tools can hide instructions for the agent. By default, Eigin asks you before it reads outside sources, and before any action with consequences.",
      },
      {
        title: "We see some traffic",
        body: "Our cloud services see your IP address temporarily, to stop abuse. They don't need your name, email or a user ID.",
      },
      {
        title: "AI can make mistakes",
        body: "Any model can be confidently wrong. Check the output before you rely on it.",
      },
    ],
  },
  responsible: {
    title: "Who's responsible",
    body: "Eigin is made by Eigin ApS, a small Danish team in Copenhagen and Aarhus. You know who we are, and you can always reach us.",
    people: [
      { name: "Daniel Rothmann", role: "Co-founder and CTO", photo: daniel },
      { name: "Therkel Sand Therkelsen", role: "Co-founder and CEO", photo: therkel },
    ],
  },
  transparency: {
    title: "Cards on the table",
    groups: [
      {
        title: "Code",
        links: [
          { label: "Source code", href: "https://code.eigin.ai/dev/eigin" },
          { label: "Technical docs", href: `${docs}/privacy.md` },
          {
            label: "Security policy",
            href: "https://code.eigin.ai/dev/eigin/-/blob/main/SECURITY.md",
          },
        ],
      },
      {
        title: "Compliance",
        links: [
          {
            label: "CASA",
            href: "https://docs.eigin.ai/compliance/casa.html",
          },
          { label: "GDPR", href: "https://docs.eigin.ai/compliance/gdpr.html" },
          { label: "AI Act", href: "https://docs.eigin.ai/compliance/ai-act.html" },
        ],
      },
      {
        title: "Policies",
        links: [
          { label: "Privacy policy", href: "/en/privacy/" },
          { label: "Terms of service", href: "/en/terms/" },
        ],
      },
      {
        title: "Talk to us",
        links: [
          { label: "Email us", href: "mailto:hello@eigin.ai" },
          { label: "Chat with us", href: "https://chat.eigin.ai" },
        ],
      },
    ],
  },
};

export default content;
