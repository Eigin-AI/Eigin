import type { HomeContent } from "./types";

const content: HomeContent = {
  title: "Eigin — AI so personal, it has to be yours.",
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
        ask: "Help me plan my day",
        tools: ["Checking your calendar…"],
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
        ask: "Should I take the new job?",
        tools: ["Looking back at what matters to you…"],
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
        label: "Find the words for a difficult conversation",
        ask: "Help me talk to my manager",
        tools: ["Thinking it through…"],
        reply:
          "Try: “I want to do this well, but three projects at once is too much. Can we decide which one comes first?”",
        options: [
          {
            label: "Help me practise",
            description: "Try the conversation together",
            symbol: "illustration/person-1",
          },
        ],
      },
      {
        label: "Hand off the busy work",
        ask: "What needs me in my inbox?",
        tools: ["Checking your connected inbox…"],
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
    body: "Eigin is built to keep your data with you and its actions in your hands. It's open source, so anyone can check it.",
    action: { label: "See how it works", href: "/en/trust/" },
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
    body: "Eigin makes it safe to connect your private agents. Share context as a team, and find what you need without asking around.",
    bullets: [
      "Find answers in shared docs and resources",
      "Turn shared notes into clear next steps",
      "Spot related work and dependencies",
      "Shared tools and guidance, set up once",
    ],
    placeholder: "Team agent diagram",
  },
  pricing: {
    title: "Free for you, fair for your team",
    body: "We think everyone should own their AI, so Eigin is free for personal use. We earn our keep with private cloud AI and commercial plans that are worth paying for.",
    action: "Ask about plans",
    plans: [
      {
        name: "Personal",
        price: "Free",
        detail: "The full app and the essential services that support it.",
      },
      {
        name: "Cloud AI",
        price: "Pay as you go",
        detail: "You pay what we pay, plus 10%. Or bring your own for free.",
      },
      {
        name: "Team",
        price: "€50 a month",
        detail: "For up to 25 people. One flat price, no per-seat nonsense.",
        status: "Coming soon",
      },
      {
        name: "Organisation",
        price: "Let's talk",
        detail: "Larger teams, self-hosting and commercial licences.",
      },
    ],
  },
  open: {
    title: "Open tech, built in Europe",
    body: "Eigin is open source and European-owned. Read the code, follow the roadmap and help us shape what comes next.",
    links: [
      {
        label: "Read the code",
        detail: "See how Eigin is built.",
        href: "https://code.eigin.ai/dev/eigin",
      },
      {
        label: "Check the roadmap",
        detail: "See what's active, planned and launched.",
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
        answer: `<p>The app is free. Cloud AI is pay as you go, so it depends on how much you use it. A typical Eigin user spends €10–20 a month, less than a ChatGPT Plus subscription.</p><p>A local model, or a provider you already pay for, costs nothing extra.</p>`,
      },
      {
        question: "Which model should I pick?",
        answer: `<p>Start with our cloud AI. It's fast, capable and runs in Europe.</p><p>Pick the local model for offline inference on your phone. Tools that contact connected services still need a network connection and your permission. It's slower and needs an iPhone 15 or later. Already pay for ChatGPT Plus or another provider? Connect it instead.</p>`,
      },
      {
        question: "Does everything stay on my phone?",
        answer: `<p>Your chats, memories and settings are stored on your phone. Cloud requests can include your conversation, relevant memories and permitted connected data. Our cloud AI runs in Europe and stores nothing.</p><p>With a local model, inference stays on your phone. Separately permitted tools can still contact connected services. <a href="/en/trust/">See how it works</a></p>`,
      },
      {
        question: "How do credits work?",
        answer: `<p>You pay for our cloud AI with credits, bought in the app. Credits never expire. They're tied to your purchase, not to an account, so there's nothing to sign up for.</p><p>On a new phone, tap <strong>Recover credits</strong> to get them back.</p>`,
      },
      {
        question: "What if I lose my phone?",
        answer: `<p>Your chats and memories are part of your phone's regular backup, like your other apps. We never see them, so we can't restore them for you.</p>`,
      },
      {
        question: "Can I use it on Android or the web?",
        answer: `<p>Not yet. Eigin is on iPhone today, and more platforms are on the way. <a href="/en/roadmap/">See our roadmap</a></p>`,
      },
      {
        question: "When is Eigin for teams coming?",
        answer: `<p>We're building it now, and we're looking for teams who want to try it early. <a href="mailto:hello@eigin.ai?subject=Eigin%20for%20teams%20early%20access">Join early access</a></p>`,
      },
    ],
    more: "Need help with the app?",
    support: { label: "Visit support", href: "/en/support/" },
  },
  get: {
    motion: { pause: "Pause illustration", play: "Play illustration" },
    title: "Make AI yours.\nStarting now.",
    visual: "Eigin on an iPhone, offering to fill in a school trip form.",
    badge: "Download on the App Store",
    more: "Coming soon to more platforms.",
    roadmap: { label: "See our roadmap", href: "/en/roadmap/" },
  },
};

export default content;
