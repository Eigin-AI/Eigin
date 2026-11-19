import { error } from "@sveltejs/kit";
import { requireReviewCall } from "#lib/server/review-access.ts";
import { selection } from "#lib/server/runtime.ts";
import type { RequestHandler } from "./$types";
export const GET: RequestHandler = async ({ locals, params }) => {
  const { user, call } = await requireReviewCall(locals.user, params.slug);
  if (params.place !== "selected" && params.place !== "runner-up")
    error(404, "Not found");
  const awarded = await selection().awarded(user, call.slug, params.place);
  if (!awarded) error(404, "Not found");
  return new Response(awarded.markdown, {
    headers: {
      "Content-Type": "text/markdown; charset=utf-8",
      "Content-Disposition": `attachment; filename="submission-${awarded.submissionId}-revision-${awarded.revisionId}.md"`,
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
};
