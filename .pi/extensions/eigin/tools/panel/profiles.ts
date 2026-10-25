/** Versioned personal portraits with source provenance outside the roleplaying text. */
import { readFile, readdir } from "node:fs/promises";
import { join } from "node:path";
import { parseFrontmatter } from "@earendil-works/pi-coding-agent";

export interface Persona {
  id: string;
  version: number;
  name: string;
  description: string;
  source: { dataset: string; revision: string; recordId: string };
  profile: string;
}

/** Load narrative Markdown profiles; invalid or duplicate profiles fail before inference. */
export async function loadPersonas(cwd: string): Promise<Persona[]> {
  const directory = join(cwd, ".pi/panel/personas");
  const names = (await readdir(directory))
    .filter((name) => name.endsWith(".md"))
    .sort();
  const profiles: Persona[] = [];
  for (const name of names) {
    const { frontmatter: p, body } = parseFrontmatter<Record<string, unknown>>(
      await readFile(join(directory, name), "utf8"),
    );
    if (
      typeof p.id !== "string" ||
      !/^[a-z][a-z0-9-]*$/.test(p.id) ||
      typeof p.version !== "number" ||
      !Number.isInteger(p.version) ||
      p.version < 1 ||
      ![p.name, p.description, p.dataset, p.revision, p.recordId].every(
        (v) => typeof v === "string" && v.trim(),
      ) ||
      !body.trim()
    )
      throw new Error(`Invalid panel profile: ${name}`);
    if (profiles.some((other) => other.id === p.id))
      throw new Error(`Duplicate panel persona: ${p.id}`);
    profiles.push({
      id: p.id,
      version: p.version,
      name: p.name as string,
      description: p.description as string,
      source: {
        dataset: p.dataset as string,
        revision: p.revision as string,
        recordId: p.recordId as string,
      },
      profile: body.trim(),
    });
  }
  if (!profiles.length)
    throw new Error("No panel personas found in .pi/panel/personas.");
  return profiles;
}

/** Resolve an explicit subset or all profiles, bounded to five independent reviews. */
export function selectPersonas(profiles: Persona[], ids?: string[]): Persona[] {
  const selected = ids ?? profiles.map((p) => p.id);
  if (
    !selected.length ||
    selected.length > 5 ||
    new Set(selected).size !== selected.length
  )
    throw new Error("Choose one to five distinct persona IDs.");
  return selected.map((id) => {
    const profile = profiles.find((p) => p.id === id);
    if (!profile)
      throw new Error(
        `Unknown panel persona: ${id}. Available: ${profiles.map((p) => p.id).join(", ")}`,
      );
    return profile;
  });
}
