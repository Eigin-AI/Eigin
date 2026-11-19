import { dev } from "$app/env";
import { error } from "@sveltejs/kit";
import { configuredCall } from "#lib/server/call.ts";
import { database, publishedCalls } from "#lib/server/runtime.ts";
import type { PageServerLoad } from "./$types";
export const load: PageServerLoad = async ({ locals, params }) => {
  if (!dev) error(404, "Not found");
  const result = await publishedCalls().result(params.slug);
  if (result)
    return {
      call: null,
      brief: "",
      submitted: false,
      closed: true,
      upcoming: false,
      result,
    };
  const effective = await publishedCalls().call(params.slug);
  if (!effective) error(404, "Not found");
  const { issueUrl } = configuredCall(params.slug);
  const { brief, ...call } = { ...effective, issueUrl };
  const submitted = locals.user
    ? ((
        await database().query(
          "SELECT EXISTS (SELECT 1 FROM submissions WHERE user_id=$1 AND call_slug=$2 AND current_revision_id IS NOT NULL) AS submitted",
          [locals.user.id, call.slug],
        )
      ).rows[0].submitted as boolean)
    : false;
  const closed = effective.status === "closed";
  const upcoming = effective.status === "upcoming";
  return { call, brief, submitted, closed, upcoming, result };
};
