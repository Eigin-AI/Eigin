import type { HomeContent } from "./types";

const content: HomeContent = {
  title: "Eigin",
  description: "Personal AI that belongs to you. Open technology, built in Europe.",
  hero: {
    headline: "AI so personal,\nit has to be yours",
    body: "Eigin is a personal AI agent built to be private, safe and under your control.",
    placeholder: "Brand illustration",
  },
  mission: {
    title: "What would you tell an AI, if you knew it was truly yours?",
    paragraphs: [
      "Our places for reflection used to be private. Now we think out loud with AI, and every word lands on a corporate server.",
      "Technology this personal should belong to the people who use it. That's why we're building Eigin.",
    ],
  },
  personal: {
    id: "personal",
    label: "For you",
    title: "The agent that knows you best",
    body: "Just talk to it. It learns what matters to you and helps with things big and small, on your terms.",
    placeholder: "Chat preview",
    chat: {
      agent: "Eigin",
      placeholder: "Chat with Eigin",
      allow: "Allow",
      examples: "Example conversations",
      play: "Play demo",
      pause: "Pause demo",
    },
    examples: [
      {
        label: "Plan your day around what matters",
        ask: "Make time for my presentation today",
        tools: ["Checking your calendar"],
        reply:
          "Your first meeting is at 10. Keep 8–9 for the presentation, before the day gets busy. Shall I put that in your calendar?",
        permission: {
          headline: "Add to calendar",
          symbol: "functional/timer",
          value: "Focus time · 8–9",
        },
      },
      {
        label: "Think through a hard decision",
        ask: "Which job offer fits my priorities?",
        tools: ["Checking your priorities"],
        reply:
          "You wanted a chance to lead a team. You also wanted more time with your sister. Which offer leaves room for both?",
        options: [
          {
            label: "Compare the offers",
            description: "Your priorities, side by side",
            symbol: "illustration/tree",
          },
        ],
      },
      {
        label: "Keep up with family life",
        ask: "Anything for kindergarten today?",
        tools: ["Checking Aula"],
        reply:
          "It’s outdoor day at kindergarten. Pack warm clothes and waterproof boots. Want a reminder before you leave?",
        options: [
          {
            label: "Set a reminder",
            description: "Pack outdoor clothes",
            symbol: "functional/timer",
          },
        ],
      },
      {
        label: "Hand off the busy work",
        ask: "Which emails need a reply today?",
        tools: ["Checking your inbox"],
        reply:
          "The plumber needs a time. You’re free Tuesday at 8. I’ve drafted a reply — you decide whether to send it.",
        permission: {
          headline: "Send a reply",
          symbol: "functional/mail",
          value: "“Tuesday at 8 works for me.”",
        },
      },
    ],
  },
  privacy: {
    title: "Private by design",
    body: "Eigin is built to keep your data with you and its actions in your hands. We build in the open, so our technology can be inspected, questioned and improved.",
    action: { label: "Learn more", href: "/en/trust/" },
    promises: [
      {
        illustration: "illustration/tree",
        title: "It lives with you",
        body: "Your personal data is stored on your own device. With a local model, it even works offline.",
      },
      {
        illustration: "illustration/person-1",
        title: "It answers to you",
        body: "It has a fixed set of tools, and it asks you before it sends or changes anything.",
      },
      {
        illustration: "illustration/bird",
        title: "It goes where you go",
        body: "Use the latest models or one on your phone. Switch any time, and your agent stays the same.",
      },
      {
        illustration: "illustration/butterfly",
        title: "It works for you alone",
        body: "No ads and no tracking. Our AI models run in Europe with zero data retention.",
      },
    ],
  },
  team: {
    id: "teams",
    label: "For teams",
    status: "Coming soon",
    title: "No one out of the loop",
    body: "Eigin makes it safe to connect your agents. Share context as a team, and find what you need without asking around.",
    bullets: [
      "Find answers in shared docs and resources",
      "Turn shared notes into clear next steps",
      "Spot related work and dependencies",
      "Shared tools and guidance, set up once",
    ],
    placeholder: "Team agent diagram",
    diagram: {
      context: ["Shared", "context"],
      description: "Five individual agents contribute to and draw on shared team knowledge.",
      pause: "Pause diagram",
      play: "Play diagram",
    },
  },
  pricing: {
    title: "Your AI. On your terms.",
    body: "Everyone should own their AI. Eigin is free for personal use, funded by optional cloud AI and commercial plans.",
    action: "Learn more",
    actionHref: "#faq",
    plans: [
      {
        name: "Personal",
        href: "#get",
        price: "Free",
        detail: "The full app and the essential services that support it.",
      },
      {
        name: "Cloud AI",
        href: "#faq",
        price: "Pay as you go",
        detail: "You pay what we pay, plus 10%. Or bring your own for free.",
      },
      {
        name: "Team",
        href: "mailto:hello@eigin.ai?subject=Eigin%20for%20teams%20early%20access",
        price: "€75 a month",
        detail: "For up to 25 people. One flat price, no per-seat nonsense.",
        status: "Coming soon",
      },
      {
        name: "Organisation",
        href: "mailto:hello@eigin.ai?subject=Eigin%20for%20organisations",
        price: "Let's talk",
        detail: "Larger teams, self-hosting and commercial licences.",
      },
    ],
  },
  open: {
    title: "Open tech, built in Denmark",
    body: "Eigin is open source and European-owned. Read the code, follow the roadmap and help us shape what comes next.",
    links: [
      {
        label: "Read the code",
        detail: "See how Eigin is built.",
        href: "https://code.eigin.ai/dev/eigin",
      },
      {
        label: "Check the roadmap",
        detail: "See what we're working on.",
        href: "/en/roadmap/",
      },
      {
        label: "Join the conversation",
        detail: "Talk to us and others on Matrix.",
        href: "https://chat.eigin.ai",
      },
    ],
  },
  faq: {
    title: "Questions",
    items: [
      {
        question: "What does it cost?",
        answer: `<p>The app is free. Our cloud AI is pay as you go. Based on our own usage, a typical month costs €10–20, depending on how much you use it.</p><p>A local model or a provider you already pay for costs nothing extra.</p>`,
      },
      {
        question: "How do I choose an AI model?",
        answer: `<p>You don't have to. Eigin automatically picks a suitable model from the provider you're using, so you don't need to know which one to choose.</p><p>Start with our cloud AI. It's fast, capable and European. If you already pay for ChatGPT Plus or another provider, you can connect that too.</p><p>You can also download a local model in the app to chat offline.</p>`,
      },
      {
        question: "Does everything stay on my device?",
        answer: `<p>Your chats, memories and settings are stored on your device. Cloud AI requests can include your conversation, relevant memories and permitted connected data.</p><p>Our cloud AI runs in Europe and doesn’t store your prompts or responses.</p><p>With a local model, your conversation stays on your device. Separately permitted tools can still contact connected services. <a href="/en/trust/">See how it works</a></p>`,
      },
      {
        question: "How do credits work?",
        answer: `<p>You pay for our cloud AI with credits bought in the app.</p><p>One credit covers roughly one euro cent of AI usage with our European AI providers. When you buy credits, the price includes the App Store fee and our 10% markup to keep things running.</p><p>Credits don't expire. They're tied directly to your purchase, so you don't need to sign up for an Eigin account.</p>`,
      },
      {
        question: "What if I lose my device?",
        answer: `<p>Your chats and memories can be restored from your device's backup, like other app data. We don't have a copy, so we can't restore them for you.</p><p>You can restore credits from the credit purchase screen in the app. Use the same Apple Account you used to buy them.</p>`,
      },
      {
        question: "Can I use it on Android or the web?",
        answer: `<p>Not yet. Eigin is on iOS today, with more platforms coming.</p><p><a href="/en/roadmap/">See our roadmap</a>.</p>`,
      },
      {
        question: "When is Eigin for teams coming?",
        answer: `<p>We're building it now, and we're looking for teams who want to try it early.</p><p><a href="mailto:hello@eigin.ai?subject=Eigin%20for%20teams%20early%20access">Join early access</a>.</p>`,
      },
    ],
    more: "Need help with the app?",
    support: { label: "Visit support", href: "/en/support/" },
  },
  get: {
    motion: { pause: "Pause illustration", play: "Play illustration" },
    title: "Make AI yours.\nStarting now.",
    visual: "Eigin on an iPhone, offering to fill in a school trip form.",
    badge: {
      eyebrow: "Join the beta",
      label: "TestFlight",
      accessibleLabel: "Join the Eigin iPhone beta on TestFlight",
    },
    instructions: "Sign up for early access on iPhone.",
    more: "Coming soon to more platforms.",
    roadmap: { label: "See our roadmap", href: "/en/roadmap/" },
  },
};

export default content;
