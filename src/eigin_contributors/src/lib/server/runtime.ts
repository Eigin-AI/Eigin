import { Publication } from "./publication.ts";
import { PublishedCalls } from "./published-calls.ts";
import { publicCalls } from "./call.ts";
import * as env from "$app/env/private";
import { dev } from "$app/env";
import { Selection } from "./selection.ts";
import { Review, isReviewer } from "./review.ts";
import type { User } from "./auth.ts";
import { Auth } from "./auth.ts";
import { createPool } from "./database.ts";

let service: Auth | undefined;
let pool: ReturnType<typeof createPool> | undefined;
export function database() {
  if (pool) return pool;
  const url = env.DATABASE_URL;
  if (!url) throw new Error("Database configuration is missing");
  return (pool = createPool(url));
}
/** Validate the canonical app origin without accepting a browser-selected host. */
export function origin() {
  const value = env.ORIGIN;
  if (!value) throw new Error("ORIGIN is required");
  const url = new URL(value);
  if (
    url.origin !== value ||
    (url.protocol !== "https:" &&
      !(
        dev &&
        url.protocol === "http:" &&
        ["localhost", "127.0.0.1"].includes(url.hostname)
      ))
  )
    throw new Error("Invalid server origin");
  return value;
}

/** Initialize only when authentication is needed; public content does not need secrets. */
export function auth() {
  if (service) return service;
  if (!env.GITLAB_CLIENT_ID || !env.GITLAB_CLIENT_SECRET)
    throw new Error("OAuth configuration is missing");
  service = new Auth(database(), {
    origin: origin(),
    clientId: env.GITLAB_CLIENT_ID,
    clientSecret: env.GITLAB_CLIENT_SECRET,
  });
  return service;
}

/** Reviewer access remains local-only until the production launch gates are ready. */
export function canReview(user: User | null): user is User {
  return dev && isReviewer(user, env.REVIEWER_GITLAB_IDS);
}

/** Create a reviewer service using private server configuration. */
export function review() {
  return new Review(database(), env.REVIEWER_GITLAB_IDS);
}

/** Private decision service; routes enforce the development launch gate. */
export function selection() {
  return new Selection(database(), env.REVIEWER_GITLAB_IDS);
}

/** Reviewer publication writes; routes retain the development-only launch gate. */
export function publication() {
  return new Publication(database(), env.REVIEWER_GITLAB_IDS);
}
/** Public snapshot reads are available only in the local rehearsal runtime. */
export function publishedCalls() {
  return new PublishedCalls(database(), publicCalls());
}
