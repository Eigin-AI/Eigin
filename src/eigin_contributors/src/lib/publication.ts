import type { ResultsCopy } from "./results-copy.ts";

/** Deliberately public call content, independent of private review records. */
export type PublicCall = {
  slug: string;
  title: string;
  summary: string;
  brief: string;
  publicListing: boolean;
  opensAt: string;
  closesAt: string;
  selectedAmountMinor: number;
  runnerUpAmountMinor: number;
  currency: string;
  displayTimezone: string;
};
/** A published revision contains no private submission identifiers or contact fields. */
export type PublicSpec = {
  author: string;
  title: string;
  markdown: string;
  amountMinor: number;
};
/** Immutable content approved for anonymous reading. */
export type PublicSnapshot = {
  slug: string;
  title: string;
  summary: string;
  brief: string;
  closesAt: string;
  currency: string;
  copy: ResultsCopy;
  selected: PublicSpec;
  runnerUp: PublicSpec;
};
export type PublicResult = Omit<
  PublicSnapshot,
  "selected" | "runnerUp" | "brief"
> & {
  selected: Omit<PublicSpec, "markdown">;
  runnerUp: Omit<PublicSpec, "markdown">;
  publishedAt: string;
};
export type PublicCallCard = Pick<
  PublicSnapshot,
  "slug" | "title" | "summary" | "closesAt"
> & {
  publishedAt: string | null;
  selectedAuthor: string | null;
  runnerUpAuthor: string | null;
};
