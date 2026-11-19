import { error, fail, redirect } from "@sveltejs/kit";
import { configuredPublicCall, submissionContract } from "#lib/server/call.ts";
import { database, origin } from "#lib/server/runtime.ts";
import {
  current,
  submit,
  SubmissionFailure,
  acceptedAgreements,
  consentStatements,
} from "#lib/server/submissions.ts";
import { boundedForm } from "#lib/server/form.ts";
import type { Actions, PageServerLoad } from "./$types";
export const load: PageServerLoad = async ({ locals, params, url }) => {
  const call = configuredPublicCall(params.slug);
  if (!locals.user) {
    const destination =
      `/calls/${params.slug}/submission` +
      (url.searchParams.has("edit") ? "?edit=1" : "");
    redirect(303, "/auth/gitlab?returnTo=" + encodeURIComponent(destination));
  }
  const terms = submissionContract(params.slug);
  const submission = await current(database(), locals.user.id, call.slug);
  return {
    call: { slug: call.slug, title: call.title },
    submission,
    statements: consentStatements(terms.mode),
    accepted: acceptedAgreements(submission, terms),
    editing: url.searchParams.has("edit"),
    closed:
      Date.now() >= Date.parse(call.closesAt) ||
      Date.now() < Date.parse(call.opensAt),
    claVersion: terms.cla.version,
    termsVersion: terms.terms.version,
    claHash: terms.cla.sha256,
    termsHash: terms.terms.sha256,
  };
};
export const actions: Actions = {
  default: async ({ request, locals, params }) => {
    configuredPublicCall(params.slug);
    const call = submissionContract(params.slug);
    if (!locals.user) error(401, "Sign in before submitting.");
    if (request.headers.get("origin") !== origin())
      error(403, "Invalid request origin.");
    const form = await boundedForm(request);
    try {
      await submit(database(), locals.user, call, form);
    } catch (e) {
      if (e instanceof SubmissionFailure)
        return fail(e.status, { message: e.message });
      return fail(503, {
        message:
          "Submission could not be confirmed. Reload your receipt before trying again.",
      });
    }
    redirect(303, `/calls/${params.slug}/submission`);
  },
};
