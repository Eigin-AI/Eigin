import { error } from "@sveltejs/kit";
import termsBody from "../../../content/guides/participation-terms.md?raw";
import claBody from "../../../../../docs/src/contributing/individual-agreement.md?raw";
import { digest, type Contract } from "./submissions.ts";

type CallMetadata = {
  slug: string;
  title: string;
  summary: string;
  opensAt: string;
  closesAt: string;
  selectedAmountMinor: number;
  runnerUpAmountMinor: number;
  currency: string;
  displayTimezone: string;
  publicListing?: boolean;
  state: string;
  issueUrl: string | null;
  decisionAt: string | null;
  termsVersion: string | null;
  termsApproved: boolean;
  eligibility: string;
};

/** Read a configured call and its authored brief. */
export function configuredCall(slug: string) {
  const metadata = callFiles[`../../../content/calls/${slug}/call.json`];
  const brief = briefFiles[`../../../content/calls/${slug}/brief.md`];
  if (!metadata || brief === undefined) error(404, "Not found");
  return { ...metadata, brief };
}
/** Resolve a call available through the public contribution routes. */
export function configuredPublicCall(slug: string) {
  const call = configuredCall(slug);
  if (call.publicListing !== true || call.slug !== slug)
    error(404, "Not found");
  return call;
}
export function submissionContract(slug: string): Contract {
  const call = configuredCall(slug);
  return {
    slug: call.slug,
    opensAt: call.opensAt,
    closesAt: call.closesAt,
    selectedAmountMinor: call.selectedAmountMinor,
    runnerUpAmountMinor: call.runnerUpAmountMinor,
    currency: call.currency,
    mode: "rehearsal",
    cla: { version: "individual-v1.0", body: claBody, sha256: digest(claBody) },
    terms: {
      version: "participation-v1",
      body: termsBody,
      sha256: digest(termsBody),
    },
  };
}

const callFiles = import.meta.glob<CallMetadata>(
  "../../../content/calls/*/call.json",
  { eager: true, import: "default" },
);
const briefFiles = import.meta.glob<string>(
  "../../../content/calls/*/brief.md",
  { eager: true, query: "?raw", import: "default" },
);

/** Retain call directories after closing so historical review keeps titles and briefs. */
export function reviewCalls() {
  return Object.entries(callFiles).map(([path, call]) => {
    if (
      !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(call.slug) ||
      !path.endsWith(`/${call.slug}/call.json`)
    )
      throw new Error("Invalid call identifier");
    return {
      slug: call.slug,
      title: call.title,
      opensAt: call.opensAt,
      closesAt: call.closesAt,
      timeZone: call.displayTimezone,
      briefHref:
        briefFiles[path.replace("call.json", "brief.md")] !== undefined
          ? call.publicListing === true
            ? `/calls/${call.slug}`
            : `/review/calls/${call.slug}/brief`
          : null,
    };
  });
}

/** A private reading fallback for configured calls without their own public route. */
export function reviewBrief(slug: string) {
  return briefFiles[`../../../content/calls/${slug}/brief.md`] ?? null;
}

/** Only deliberately listed metadata may appear outside private review. */
export function publicCalls() {
  reviewCalls();
  return Object.entries(callFiles).flatMap(([path, call]) => {
    const brief = briefFiles[path.replace("call.json", "brief.md")];
    return call.publicListing === true && brief !== undefined
      ? [
          {
            slug: call.slug,
            title: call.title,
            summary: call.summary,
            brief,
            publicListing: true,
            opensAt: call.opensAt,
            closesAt: call.closesAt,
            selectedAmountMinor: call.selectedAmountMinor,
            runnerUpAmountMinor: call.runnerUpAmountMinor,
            currency: call.currency,
            displayTimezone: call.displayTimezone,
          },
        ]
      : [];
  });
}
