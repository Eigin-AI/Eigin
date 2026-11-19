import { dev } from "$app/env";
import type { Handle } from "@sveltejs/kit/hooks";
import { auth } from "./lib/server/runtime.ts";

export const handle: Handle = async ({ event, resolve }) => {
  event.locals.user = null;
  const route = event.route.id ?? "";
  // Call workflows remain gated until launch approval.
  if (!dev && /^\/(calls|review)(\/|$)/.test(route)) {
    return new Response("Calls and submissions are not available yet.", {
      status: 404,
      headers: { "Cache-Control": "no-store" },
    });
  }
  const token = event.cookies.get("contributors_session");
  if (token && route !== "/auth/callback" && route !== "/auth/gitlab") {
    try {
      event.locals.user = await auth().user(token);
    } catch {
      return new Response(
        "Sign-in is temporarily unavailable. Please try again.",
        { status: 503, headers: { "Cache-Control": "no-store" } },
      );
    }
    if (!event.locals.user)
      event.cookies.delete("contributors_session", { path: "/" });
  }
  const response = await resolve(event);
  response.headers.set("Cache-Control", "no-store");
  response.headers.set("X-Content-Type-Options", "nosniff");
  response.headers.set(
    "Referrer-Policy",
    route.startsWith("/auth/") ? "no-referrer" : "same-origin",
  );
  return response;
};
