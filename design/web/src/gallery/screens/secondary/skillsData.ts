export interface Skill {
  id: string;
  name: string;
  description: string;
  /** Controls the skill is active with, always or once its capability connects. */
  tools: string[];
  /** Integration capability that must connect before the skill becomes available. */
  capabilities: string[];
}

// Bundled skills; integration-gated ones carry the tools their capability adds.
export const skills: Skill[] = [
  {
    id: "knowledge",
    name: "Knowledge",
    description: "Remember and recall information using your knowledge base.",
    tools: [
      "Search Knowledge",
      "Get Knowledge",
      "Add Knowledge",
      "Update Knowledge",
      "Delete Knowledge",
      "Forget Knowledge",
      "Supersede Knowledge",
      "Merge Knowledge",
      "Flag Knowledge Conflict",
    ],
    capabilities: [],
  },
  {
    id: "intents",
    name: "Intents",
    description: "Set goals and track what matters to the user across conversations.",
    tools: ["Add Intent", "Update Intent", "List Intents", "Resolve Intent"],
    capabilities: [],
  },
  {
    id: "awareness",
    name: "Awareness",
    description: "Know the current time and place, find places, estimate trips, and check weather.",
    tools: ["Time and Place", "Search Places", "Directions", "Weather"],
    capabilities: [],
  },
  {
    id: "interaction",
    name: "Interaction",
    description: "Rich interaction tools for presenting choices and collecting input.",
    tools: ["Present Options"],
    capabilities: [],
  },
  {
    id: "web",
    name: "Web",
    description: "Search the web and fetch pages for up-to-date information.",
    tools: ["Web Search", "Web Fetch"],
    capabilities: [],
  },
  {
    id: "self_modification",
    name: "Self-Modification",
    description: "Change your identity, personality, voice, and behavior.",
    tools: [
      "Read Core",
      "Edit Core",
      "Get Presentation",
      "Set Presentation",
      "Set Proactivity",
      "Manage Vocabulary",
    ],
    capabilities: [],
  },
  {
    id: "email",
    name: "Email",
    description: "Draft and, if connected, read and send email.",
    tools: ["List Emails", "Search Emails", "Read Email", "Send Email", "Reply to Email"],
    capabilities: ["email"],
  },
  {
    id: "organization",
    name: "Organization",
    description: "Manage spaces, move chats and browse chat history.",
    tools: [
      "Create Space",
      "Edit Space",
      "List Spaces",
      "Move Chat to Space",
      "List Chats",
      "Get Chat Transcript",
    ],
    capabilities: [],
  },
  {
    id: "calendar",
    name: "Calendar",
    description: "Read and manage calendar events.",
    tools: ["Get Calendar Events", "Create Calendar Event", "Manage Calendar Event"],
    capabilities: ["calendar"],
  },
  {
    id: "reminders",
    name: "Reminders",
    description: "Read and manage reminders.",
    tools: ["Get Reminders", "Manage Reminder"],
    capabilities: ["reminders"],
  },
  {
    id: "planning",
    name: "Planning",
    description: "Plan an upcoming trip, event, day out, gathering, festival, or conference.",
    tools: ["Start Flow", "Advance Flow"],
    capabilities: [],
  },
  {
    id: "health",
    name: "Health",
    description: "Understand and look after your health: nutrition, activity, sleep, and vitals.",
    tools: [
      "Get Health Log",
      "Search Food",
      "Get Food Details",
      "Log Food",
      "Log Body Measurement",
      "Log Sleep",
    ],
    capabilities: ["health"],
  },
  {
    id: "cooking",
    name: "Cooking",
    description: "Decide what to cook and walk through cooking it, step by step.",
    tools: ["Start Flow", "Advance Flow"],
    capabilities: [],
  },
  {
    id: "recommendations",
    name: "Recommendations",
    description: "Find a book, movie, album, or game worth your time.",
    tools: ["Start Flow", "Advance Flow"],
    capabilities: [],
  },
  {
    id: "aula",
    name: "Aula",
    description: "Get school and daycare updates from a connected Aula account.",
    tools: [
      "Aula Updates",
      "Aula Children",
      "List Aula Messages",
      "Read Aula Message",
      "Aula Calendar",
    ],
    capabilities: ["aula"],
  },
];
