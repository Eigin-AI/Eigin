import { error } from "@sveltejs/kit";
import { requireReviewCall } from "#lib/server/review-access.ts";
import { review, selection } from "#lib/server/runtime.ts";
import type { LayoutServerLoad } from "./$types";

export const load: LayoutServerLoad = async ({ locals, url, params }) => {
  const { user, call } = await requireReviewCall(locals.user, params.slug);
  const page = url.searchParams.get("page") ?? "1";
  if (!/^[1-9]\d{0,3}$/.test(page)) error(404, "Not found");
  return {
    call,
    hasResultsDraft: !!(await selection().draft(user, call.slug)),
    recordedSelection: await selection().current(user, call.slug),
    ...(await review().list(user, call.slug, Number(page))),
  };
};
