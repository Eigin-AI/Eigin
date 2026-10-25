/** Resolve Pi's extension dependencies for standalone Node tests, without project installs. */
import { execFileSync } from "node:child_process";
import { registerHooks } from "node:module";
import { pathToFileURL } from "node:url";

const globalRoot = execFileSync("npm", ["root", "-g"], {
  encoding: "utf8",
}).trim();
const piRoot = `${globalRoot}/@earendil-works/pi-coding-agent`;
registerHooks({
  resolve(specifier, context, nextResolve) {
    try {
      return nextResolve(specifier, context);
    } catch (error) {
      const target =
        specifier === "@earendil-works/pi-coding-agent"
          ? `${piRoot}/dist/index.js`
          : specifier === "typebox"
            ? `${piRoot}/node_modules/typebox/build/index.mjs`
            : undefined;
      if (!target) throw error;
      return { url: pathToFileURL(target).href, shortCircuit: true };
    }
  },
});
