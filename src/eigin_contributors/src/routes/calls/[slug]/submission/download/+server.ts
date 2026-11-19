import { error } from "@sveltejs/kit";
import { configuredPublicCall } from "#lib/server/call.ts";
import { database } from "#lib/server/runtime.ts";
import { current } from "#lib/server/submissions.ts";
import type { RequestHandler } from "./$types";
export const GET: RequestHandler = async ({ locals, params }) => {
  const call = configuredPublicCall(params.slug);
  if (!locals.user) error(404, "Not found");
  const saved = await current(database(), locals.user.id, call.slug);
  if (!saved) error(404, "Not found");
  return new Response(saved.markdown, {
    headers: {
      "Content-Type": "text/markdown; charset=utf-8",
      "Content-Disposition": `attachment; filename="${call.slug}-${saved.id}.md"`,
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
};
