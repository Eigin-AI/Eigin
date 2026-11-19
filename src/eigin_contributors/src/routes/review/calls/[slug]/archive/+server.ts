import { error } from "@sveltejs/kit";
import { requireReviewCall } from "#lib/server/review-access.ts";
import { review } from "#lib/server/runtime.ts";
import { ReviewLimit } from "#lib/server/review.ts";
import type { RequestHandler } from "./$types";

export const GET: RequestHandler = async ({ locals, params }) => {
  const { user } = await requireReviewCall(locals.user, params.slug);
  let bytes: Uint8Array;
  try {
    bytes = await review().archive(user, params.slug);
  } catch (failure) {
    if (failure instanceof ReviewLimit) error(413, failure.message);
    throw failure;
  }
  return new Response(Uint8Array.from(bytes).buffer, {
    headers: {
      "Content-Type": "application/zip",
      "Content-Disposition": `attachment; filename="${params.slug}-submissions.zip"`,
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
};
