import { error, fail, redirect } from "@sveltejs/kit";
import { requireReviewCall } from "#lib/server/review-access.ts";
import { publicCalls } from "#lib/server/call.ts";
import { origin, publication } from "#lib/server/runtime.ts";
import { boundedForm } from "#lib/server/form.ts";
import { SelectionFailure } from "#lib/server/selection-store.ts";
import type { Actions, PageServerLoad, RequestEvent } from "./$types";

export const load: PageServerLoad = async ({ locals, params }) => {
  const { user, call } = await requireReviewCall(locals.user, params.slug);
  if (await publication().status(user, call.slug))
    redirect(303, `/review/calls/${call.slug}/selection`);
  return {};
};
async function run(
  event: RequestEvent,
  operation: "prepare" | "publish" | "cancel",
) {
  const { locals, params, request, cookies } = event;
  const { user, call } = await requireReviewCall(locals.user, params.slug);
  if (request.headers.get("origin") !== origin())
    error(403, "Invalid request origin.");
  const fields = await boundedForm(request, 4096);
  const session = cookies.get("contributors_session") ?? "";
  const token = String(fields.get("confirmationToken") ?? "");
  const metadata =
    publicCalls().find((entry) => entry.slug === call.slug) ?? null;
  try {
    if (operation === "prepare")
      return {
        prepared: await publication().prepare(
          user,
          session,
          call.slug,
          metadata,
        ),
      };
    if (operation === "cancel")
      await publication().cancel(user, session, call.slug, token);
    else
      await publication().publish(
        user,
        session,
        call.slug,
        metadata,
        token,
        String(fields.get("confirmationText") ?? ""),
      );
  } catch (e) {
    if (e instanceof SelectionFailure)
      return fail(e.status, { message: e.message });
    return fail(503, {
      message:
        "Publication could not be confirmed. Reload the selection to check its status.",
    });
  }
  redirect(303, `/review/calls/${call.slug}/selection`);
}
export const actions: Actions = {
  prepare: (event) => run(event, "prepare"),
  publish: (event) => run(event, "publish"),
  cancel: (event) => run(event, "cancel"),
};
