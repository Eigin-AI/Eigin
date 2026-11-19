import { error } from "@sveltejs/kit";
import { requireReviewCall } from "#lib/server/review-access.ts";
import { review } from "#lib/server/runtime.ts";
import type { RequestHandler } from "./$types";

export const GET: RequestHandler = async ({ locals, params }) => {
  const { user, call } = await requireReviewCall(locals.user, params.slug);
  const selected = await review().detail(user, call.slug, params.submissionId);
  if (!selected) error(404, "Not found");
  return new Response(selected.markdown, {
    headers: {
      "Content-Type": "text/markdown; charset=utf-8",
      "Content-Disposition": `attachment; filename="submission-${selected.id}-revision-${selected.revisionId}.md"`,
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
};
