/**
 * What a data card needs to ask of an arbitrary JSON value: what is a leaf,
 * what can be a table, what a thing should be called. Kept apart from the
 * rendering so the rules can be read — and argued with — on their own.
 */

import type { Json } from "./types";

export function isRecord(value: Json): value is { [key: string]: Json } {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** A leaf is anything that can be shown as one value: no children to walk. */
export function isLeaf(value: Json): boolean {
  return !isRecord(value) && !Array.isArray(value);
}

/**
 * An array of objects that all carry the same keys — a list of records, which
 * is the one array shape a table can show honestly.
 */
export function uniformColumns(value: Json): string[] | null {
  if (!Array.isArray(value) || value.length === 0) return null;
  const rows: { [key: string]: Json }[] = [];
  for (const row of value) {
    if (!isRecord(row)) return null;
    rows.push(row);
  }

  const columns = Object.keys(rows[0]);
  if (columns.length === 0) return null;

  const sameShape = rows.every((row) => {
    const keys = Object.keys(row);
    return keys.length === columns.length && keys.every((key) => columns.includes(key));
  });
  if (!sameShape) return null;

  // A column of objects is a table of tables; that is a tree's job, not a grid's.
  return rows.every((row) => columns.every((key) => isLeaf(row[key]))) ? columns : null;
}

/** Every leaf in the document, addressed by the path that reaches it. */
export function flatten(value: Json, prefix = ""): { path: string; value: Json }[] {
  if (Array.isArray(value)) {
    return value.flatMap((item, index) => flatten(item, `${prefix}[${index}]`));
  }
  if (isRecord(value)) {
    return Object.keys(value).flatMap((key) =>
      flatten(value[key], prefix ? `${prefix}.${key}` : key),
    );
  }
  return [{ path: prefix, value }];
}

/** How many leaves sit under a value, for a collapsed node's summary. */
export function countLeaves(value: Json): number {
  return flatten(value).length;
}

/**
 * `request_id` and `startsAt` are how the payload spells it, not how a person
 * reads it. Array indices keep their brackets: they are position, not a name.
 */
export function formatLabel(key: string): string {
  if (/^\[\d+\]$/.test(key)) return key;
  const spaced = key
    .replace(/[._]/g, " ")
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .toLowerCase();
  return spaced.charAt(0).toUpperCase() + spaced.slice(1);
}

/** The last segment of a path, so a grouped view can drop the parent. */
export function lastSegment(path: string): string {
  const parts = path.split(".");
  return parts[parts.length - 1];
}

/**
 * Values carry their type in how they read: a missing value says so in words
 * rather than rendering as empty, and a boolean reads as yes or no.
 */
export function formatValue(value: Json): string {
  if (value === null) return "None";
  if (typeof value === "boolean") return value ? "Yes" : "No";
  if (typeof value === "number") return String(value);
  if (typeof value === "string") return value.length === 0 ? "Empty" : value;
  return JSON.stringify(value);
}

/**
 * Long enough that it would not sit on one line beside its label, and so
 * belongs underneath it.
 *
 * Judged on the text as rendered down the iOS side — a joined list of values
 * reads as prose once it is long, as does every string past the same line.
 *
 * A character count is a proxy. What actually decides a wrap is the room left
 * after the label, which differs by row: the label column is sized to its own
 * label, and every level of nesting takes another step of width. Measuring
 * the text against that room is the honest test; this approximates it at the
 * width the card usually has.
 */
export function isProse(value: Json): boolean {
  return typeof value === "string" && value.length > 30;
}

/** An array with no structure inside it: a set of values, not of records. */
export function isScalarArray(value: Json): value is Json[] {
  return Array.isArray(value) && value.length > 0 && value.every(isLeaf);
}

/**
 * Keys that name the thing they sit on. An array item titled "rituals.md"
 * reads as itself; the same item called "[0]" reads as a position in a
 * structure nobody asked about.
 */
const namingKeys = ["title", "name", "label", "summary", "note", "subject", "key", "id"];

/** What to call one item of an array: what it is, or failing that, where it is. */
export function itemLabel(item: Json, index: number): string {
  if (isRecord(item)) {
    for (const key of namingKeys) {
      const candidate = item[key];
      if (typeof candidate === "string" && candidate.length > 0 && candidate.length <= 40) {
        return candidate;
      }
    }
  }
  return `Item ${index + 1}`;
}

/** The naming key an item spent on its own label, so it is not repeated inside. */
export function spentKey(item: Json): string | null {
  if (!isRecord(item)) return null;
  for (const key of namingKeys) {
    const candidate = item[key];
    if (typeof candidate === "string" && candidate.length > 0 && candidate.length <= 40) {
      return key;
    }
  }
  return null;
}
