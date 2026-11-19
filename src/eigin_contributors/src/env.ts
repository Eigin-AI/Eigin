import { defineEnvVars } from "@sveltejs/kit/env";
const optional = { schema: (value: string | undefined) => value };
/** Server-only runtime configuration; authentication validates required values. */
export const variables = defineEnvVars({
  ORIGIN: optional,
  DATABASE_URL: optional,
  GITLAB_CLIENT_ID: optional,
  GITLAB_CLIENT_SECRET: optional,
  REVIEWER_GITLAB_IDS: optional,
});
