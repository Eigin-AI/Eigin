import type { IconName } from "@lib";

/** Canonical types from design/knowledge/schemas.firm. */
export const knowledgeIcons = {
  Actor: "functional/avatar",
  Thing: "functional/box",
  Fact: "functional/asterix",
  Output: "functional/document",
  Note: "functional/list_check",
} satisfies Record<string, IconName>;

export const relationshipLabels = {
  relates_to: "Relates to",
  belongs_to: "Belongs to",
  uses: "Uses",
  describes: "Describes",
  supersedes: "Supersedes",
} as const;

export type KnowledgeValue = string | number | boolean | string[];
type CommonFields = Partial<Record<keyof typeof relationshipLabels, string[]>> & {
  tags?: string[];
  created_at?: string;
  [field: string]: KnowledgeValue | undefined;
};

/** Required content differs by type; additional fields remain optional. */
export type KnowledgeRecord = { id: string } & (
  | {
      kind: "Actor";
      fields: CommonFields & { name: string; type?: "human" | "ai" | "organization" | "other" };
    }
  | {
      kind: "Thing";
      fields: CommonFields & {
        name: string;
        category?: "physical" | "digital" | "place" | "service" | "concept" | "other";
      };
    }
  | {
      kind: "Fact";
      fields: CommonFields & { claim: string; name?: string; last_verified?: string };
    }
  | { kind: "Output"; fields: CommonFields & { name: string; content: string; authors?: string[] } }
  | { kind: "Note"; fields: CommonFields & { content: string } }
);

/** Presentation values derived from stored fields, without inferred descriptions. */
export type KnowledgeEntity = KnowledgeRecord & { name: string; description?: string };

/** Humanize readable IDs; keep opaque identifiers intact. */
export function fieldLabel(value: string): string {
  const words = value.replace(/_/g, " ");
  return words.charAt(0).toUpperCase() + words.slice(1);
}

/** The main text is a claim for facts, or content for outputs and notes. */
export function presentKnowledge(record: KnowledgeRecord): KnowledgeEntity {
  const storedName = record.fields.name;
  const name =
    typeof storedName === "string" && storedName.trim()
      ? storedName
      : /^[a-z]+(?:_[a-z]+)*$/.test(record.id)
        ? fieldLabel(record.id)
        : record.id;
  const content =
    record.kind === "Fact"
      ? record.fields.claim
      : record.kind === "Output" || record.kind === "Note"
        ? record.fields.content
        : undefined;
  return { ...record, name, description: content };
}

/** Fields already rendered as title, body, tags or relationships are excluded. */
export function additionalFields(entity: KnowledgeEntity): [string, string][] {
  const primary =
    entity.kind === "Fact"
      ? "claim"
      : entity.kind === "Output" || entity.kind === "Note"
        ? "content"
        : undefined;
  return Object.entries(entity.fields).flatMap(([key, value]) => {
    if (
      key === "name" ||
      key === primary ||
      key === "tags" ||
      key in relationshipLabels ||
      value === undefined ||
      value === "" ||
      (Array.isArray(value) && !value.length)
    )
      return [];
    return [[fieldLabel(key), Array.isArray(value) ? value.join(" · ") : String(value)]];
  });
}
