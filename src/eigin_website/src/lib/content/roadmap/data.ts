import type { RoadmapData } from "./types";

/** Editable roadmap entries, grouped by status and ordered for display. */
export const roadmapData: RoadmapData = {
  active: [
    {
      id: "sdk",
      copy: {
        en: {
          title: "Eigin SDK",
          description: "Implement personal agents anywhere with a shared, cross-platform SDK.",
        },
        da: {
          title: "Eigin SDK",
          description: "Byg personlige agenter overalt med et fælles SDK på tværs af platforme.",
        },
      },
    },
  ],
  planned: [
    {
      id: "sync-engine",
      copy: {
        en: {
          title: "Sync engine",
          description: "Synchronise agent data between devices with end-to-end encryption.",
        },
        da: {
          title: "Synkroniseringsmotor",
          description: "Synkronisér agentdata mellem enheder med ende-til-ende-kryptering.",
        },
      },
    },
    {
      id: "web",
      copy: {
        en: { title: "Eigin for web", description: "Use your personal agent from a browser." },
        da: { title: "Eigin på nettet", description: "Brug din personlige agent fra en browser." },
      },
    },
    {
      id: "teams",
      copy: {
        en: {
          title: "Teams",
          description:
            "Give everyone their own agent, with shared context, resources and integrations.",
        },
        da: {
          title: "Teams",
          description:
            "Giv alle deres egen agent med fælles kontekst, ressourcer og integrationer.",
        },
      },
    },
  ],
  launched: [
    {
      id: "launched",
      items: [
        {
          id: "ios",
          copy: {
            en: {
              title: "Eigin for iOS",
              description:
                "A personal agent on your iPhone, with your choice of model and memory stored on your device.",
            },
            da: {
              title: "Eigin til iOS",
              description:
                "En personlig agent på din iPhone med en model, du vælger, og hukommelsen gemt på din enhed.",
            },
          },
          version: { label: "1.0" },
        },
        {
          id: "relay",
          copy: {
            en: {
              title: "Eigin Relay",
              description: "Private connectivity services for Eigin agents.",
            },
            da: {
              title: "Eigin Relay",
              description: "Private forbindelsestjenester til Eigin-agenter.",
            },
          },
          version: { label: "1.0" },
        },
      ],
    },
  ],
};
