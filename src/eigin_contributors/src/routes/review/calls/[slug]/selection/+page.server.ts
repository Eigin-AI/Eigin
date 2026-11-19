import { error, fail, redirect } from "@sveltejs/kit";
import { requireReviewCall } from "#lib/server/review-access.ts";
import { publicCalls } from "#lib/server/call.ts";
import { origin, selection, publication } from "#lib/server/runtime.ts";
import { boundedForm } from "#lib/server/form.ts";
import {
  SelectionFailure,
  type Pair,
  type SelectionSummary,
} from "#lib/server/selection.ts";
import { validateCopy } from "#lib/server/selection-drafts.ts";
import {
  emptyResultsCopy,
  resultsFields,
  type ResultsCopy,
} from "#lib/results-copy.ts";
import type { Actions, PageServerLoad, RequestEvent } from "./$types";

function values(fields: URLSearchParams | FormData) {
  const last = (key: string) =>
    String(fields.getAll(key).at(-1) ?? "").slice(0, 50);
  return { selected: last("selected"), runnerUp: last("runnerUp") };
}
function pair(fields: ReturnType<typeof values>): Pair {
  const choice = (value: string) => {
    const [submissionId = "", revisionId = "", extra] = value.split(":");
    return {
      submissionId: extra === undefined ? submissionId : "",
      revisionId,
    };
  };
  return {
    selected: choice(fields.selected),
    runnerUp: choice(fields.runnerUp),
  };
}
function choiceValues(chosen: Pair) {
  return {
    selected: `${chosen.selected.submissionId}:${chosen.selected.revisionId}`,
    runnerUp: `${chosen.runnerUp.submissionId}:${chosen.runnerUp.revisionId}`,
  };
}
export const load: PageServerLoad = async ({ locals, params, url }) => {
  const { user, call } = await requireReviewCall(locals.user, params.slug);
  const recorded = await selection().current(user, call.slug);
  const draft = await selection().draft(user, call.slug);
  const savedChoices = draft
    ? choiceValues(draft.pair)
    : { selected: "", runnerUp: "" };
  const choices =
    url.searchParams.has("selected") || url.searchParams.has("runnerUp")
      ? values(url.searchParams)
      : savedChoices;
  const copy = { ...(draft?.copy ?? emptyResultsCopy) };
  if (choices.selected !== savedChoices.selected) {
    copy.selectedSummary = "";
  }
  if (choices.runnerUp !== savedChoices.runnerUp) {
    copy.runnerUpSummary = "";
  }
  let summary: SelectionSummary | null = null;
  let message = "";
  const resumeDraft =
    !!draft &&
    !url.searchParams.has("step") &&
    !url.searchParams.has("selected") &&
    !url.searchParams.has("runnerUp") &&
    !url.searchParams.has("page");
  if (!recorded && (url.searchParams.get("step") === "write" || resumeDraft)) {
    try {
      summary = await selection().summary(user, call.slug, pair(choices));
    } catch (e) {
      if (e instanceof SelectionFailure) message = e.message;
      else throw e;
    }
  }
  return {
    choices,
    recorded,
    publicationStatus: await publication().status(user, call.slug),
    canPublish: publicCalls().some((entry) => entry.slug === call.slug),
    summary,
    message,
    copy,
    draftVersion: draft?.version ?? "0",
    hasDraft: !!draft,
  };
};

async function save(event: RequestEvent, preview: boolean) {
  const { locals, params, request, cookies } = event;
  const { user, call } = await requireReviewCall(locals.user, params.slug);
  if (request.headers.get("origin") !== origin())
    error(403, "Invalid request origin.");
  const fields = await boundedForm(request, 192 * 1024);
  const choices = values(fields);
  const copy = Object.fromEntries(
    resultsFields.map(({ key }) => {
      const value = fields.get(key);
      return [key, typeof value === "string" ? value : ""];
    }),
  ) as ResultsCopy;
  const version = String(fields.get("draftVersion") ?? "");
  let summary: SelectionSummary | null = null;
  try {
    summary = await selection().summary(user, call.slug, pair(choices));
    validateCopy(copy, preview);
    const nextVersion = await selection().saveDraft(
      user,
      cookies.get("contributors_session") ?? "",
      call.slug,
      pair(choices),
      copy,
      version,
    );
    if (preview)
      return {
        confirmation: await selection().prepare(
          user,
          cookies.get("contributors_session") ?? "",
          call.slug,
          pair(choices),
          nextVersion,
        ),
      };
  } catch (e) {
    const editing = { choices, copy, version, summary };
    if (e instanceof SelectionFailure)
      return fail(e.status, { message: e.message, editing });
    return fail(503, {
      message:
        "The results draft could not be confirmed. Keep your text and reload the saved draft before trying again.",
      editing,
    });
  }
  redirect(303, `/review/calls/${call.slug}/selection?step=write&saved=1`);
}

export const actions: Actions = {
  saveDraft: (event) => save(event, false),
  preview: (event) => save(event, true),
  cancel: async ({ locals, params, request, cookies }) => {
    const { user, call } = await requireReviewCall(locals.user, params.slug);
    if (request.headers.get("origin") !== origin())
      error(403, "Invalid request origin.");
    const fields = await boundedForm(request, 4096);
    try {
      await selection().cancel(
        user,
        cookies.get("contributors_session") ?? "",
        call.slug,
        String(fields.get("confirmationToken") ?? ""),
      );
    } catch (e) {
      if (e instanceof SelectionFailure)
        return fail(e.status, { message: e.message });
      return fail(503, {
        message:
          "Cancellation could not be confirmed. Reload this page before continuing.",
      });
    }
    redirect(303, `/review/calls/${call.slug}/selection?step=write`);
  },
  confirm: async ({ locals, params, request, cookies }) => {
    const { user, call } = await requireReviewCall(locals.user, params.slug);
    if (request.headers.get("origin") !== origin())
      error(403, "Invalid request origin.");
    const fields = await boundedForm(request, 4096);
    if (await selection().current(user, call.slug))
      redirect(303, `/review/calls/${call.slug}/selection?existing=1`);
    try {
      await selection().confirm(
        user,
        cookies.get("contributors_session") ?? "",
        call.slug,
        String(fields.get("confirmationToken") ?? ""),
        String(fields.get("confirmationText") ?? ""),
      );
    } catch (e) {
      if (e instanceof SelectionFailure)
        return fail(e.status, {
          message: `${e.message} No new selection was recorded.`,
        });
      return fail(503, {
        message:
          "Selection could not be confirmed. Reload the recorded selection before trying again.",
      });
    }
    redirect(303, `/review/calls/${call.slug}/selection`);
  },
};
