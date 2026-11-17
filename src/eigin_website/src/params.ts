import { defineParams } from "@sveltejs/kit/params";
import { isUnlocalizedSection } from "#lib/unlocalized.ts";

/** Match only known language-free page sections, leaving unknown URLs as 404s. */
export const params = defineParams({
  unlocalized: (value) => (isUnlocalizedSection(value) ? value : undefined),
});
