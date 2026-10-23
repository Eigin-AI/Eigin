import {
  presentKnowledge,
  relationshipLabels,
  type KnowledgeRecord,
  type KnowledgeEntity,
} from "../knowledgeData";
export { knowledgeIcons } from "../knowledgeData";
export type GraphEntity = KnowledgeEntity;

// Schema-shaped samples; names and descriptions are never inferred from relationships.
const records: KnowledgeRecord[] = [
  {
    id: "user",
    kind: "Actor",
    fields: {
      name: "You",
      type: "human",
      tags: ["Personal"],
      created_at: "2026-10-19T09:00:00Z",
      relates_to: [
        "sofie",
        "trip",
        "eigin",
        "train",
        "cooking",
        "garden",
        "books",
        "cycling",
        "norwegian",
        "hotel",
      ],
    },
  },
  {
    id: "sofie",
    kind: "Actor",
    fields: {
      name: "Sofie",
      relates_to: ["trip", "cooking", "garden"],
    },
  },
  {
    id: "trip",
    kind: "Thing",
    fields: {
      name: "Summer trip",
      category: "concept",
      relates_to: ["train", "oslo", "hotel", "itinerary"],
    },
  },
  {
    id: "eigin",
    kind: "Thing",
    fields: {
      name: "Eigin",
      category: "digital",
    },
  },
  {
    id: "train",
    kind: "Fact",
    fields: {
      name: "Train travel",
      claim: "You prefer trains for journeys within Scandinavia, especially overnight services.",
      tags: ["Travel"],
      last_verified: "2026-10-20T12:30:00Z",
      relates_to: ["oslo"],
    },
  },
  {
    id: "cooking",
    kind: "Thing",
    fields: {
      name: "Cooking",
      relates_to: ["garden"],
    },
  },
  {
    id: "garden",
    kind: "Thing",
    fields: {
      name: "Garden",
    },
  },
  {
    id: "oslo",
    kind: "Thing",
    fields: {
      name: "Oslo",
      category: "place",
      relates_to: ["itinerary", "norwegian"],
    },
  },
  {
    id: "books",
    kind: "Thing",
    fields: {
      name: "Books",
    },
  },
  {
    id: "cycling",
    kind: "Fact",
    fields: {
      name: "Cycling",
      claim: "Your usual way to get around Copenhagen.",
    },
  },
  {
    id: "norwegian",
    kind: "Thing",
    fields: {
      name: "Learning Norwegian",
    },
  },
  {
    id: "hotel",
    kind: "Fact",
    fields: {
      name: "Small independent hotels",
      claim: "You like smaller places to stay, away from the busiest streets.",
    },
  },
  {
    id: "itinerary",
    kind: "Output",
    fields: {
      name: "Oslo weekend itinerary",
      content:
        "Friday: Take the afternoon train from Copenhagen to Oslo. Bring something to read and pick up dinner before boarding. Check in at a small hotel near the station, then take a short walk along the waterfront if there is time.\n\nSaturday: Start with coffee and breakfast in Grünerløkka. Leave the morning open for bookshops and a walk beside the river. Visit the National Museum after lunch, with enough time to explore without rushing. Find a quiet restaurant for dinner and book a table earlier in the day.\n\nSunday: Have a slow breakfast, pack, and leave the bags at the hotel. Walk through the botanical garden before collecting them. Allow plenty of time to reach the station, buy food for the journey, and find the return train.\n\nBefore leaving: Check train reservations, museum opening hours, and the weather forecast. Save tickets offline and bring a light waterproof jacket.",
      authors: ["user"],
    },
  },
  {
    id: "note",
    kind: "Note",
    fields: {
      content: "A saved thought with no relationships yet.",
    },
  },
  {
    id: "quiet_workspaces",
    kind: "Fact",
    fields: {
      claim: "Quiet places make it easier to concentrate on writing.",
    },
  },
  ...[
    "Copenhagen",
    "Aarhus",
    "Odense",
    "Aalborg",
    "Roskilde",
    "Bergen",
    "Trondheim",
    "Stavanger",
    "Kristiansand",
    "Tromsø",
    "Stockholm",
    "Gothenburg",
    "Malmö",
    "Uppsala",
    "Lund",
    "Helsinki",
    "Turku",
    "Tampere",
    "Reykjavík",
    "Akureyri",
  ].map((name, index): KnowledgeRecord => ({
    id: `saved_place_${index + 1}`,
    kind: "Thing",
    fields: { name, category: "place" },
  })),
];

export const entities = records.map(presentKnowledge);
export const entityByID = new Map(entities.map((entity) => [entity.id, entity]));

/** Directed links retain the actual stored predicate for detail views. */
export const links = records.flatMap((record) =>
  Object.keys(relationshipLabels).flatMap((key) => {
    const type = key as keyof typeof relationshipLabels;
    return (record.fields[type] ?? []).map((target) => ({ source: record.id, target, type }));
  }),
);

/** Both incoming and outgoing relationships, with their stored type. */
export function relationships(id: string) {
  return links.flatMap((link) => {
    const incoming = link.target === id;
    const otherID = link.source === id ? link.target : incoming ? link.source : undefined;
    if (!otherID) return [];
    const entity = entityByID.get(otherID);
    if (!entity) return [];
    return [{ entity, label: relationshipLabels[link.type] + (incoming ? " · Incoming" : "") }];
  });
}

/** Unique immediate neighbors; the graph never expands a second ring. */
export function neighbors(id: string): GraphEntity[] {
  return [...new Map(relationships(id).map(({ entity }) => [entity.id, entity])).values()];
}
