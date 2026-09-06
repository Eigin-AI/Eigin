/**
 * Every class and CSS custom property a template uses must be defined.
 *
 * Class names in markup and `var(--token)` references are plain strings: no
 * compiler checks that `t-titleS` or `--color-accent` refer to anything, and
 * the generated styles live in gitignored files, so a typo is silent until
 * the type looks wrong on screen. This walks every `.svelte` file, collects
 * the tokens used in `class=` attributes and `var(--…)` references, and
 * fails for any with no definition in a `<style>` block, a CSS file, or the
 * generated CSS.
 */
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

const src = "src";
const generated = "src/lib/generated";

// The whole attribute string counts when it holds an expression:
// class="card {size}" declares card, large, small and compact together.
const defined = new Set();
const definedVars = new Set();
const used = new Map(); // token -> first "file:line"
const usedVars = new Map();

function walk(dir, fn) {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) walk(path, fn);
    else fn(path);
  }
}

/* Collect every class and custom property a definition site declares.
   Class selectors match bare names: `.card` yields "card". */
const collectDefinitions = (text) => {
  for (const m of text.matchAll(/\.([a-zA-Z][\w-]*)/g)) defined.add(m[1]);
  for (const m of text.matchAll(/(--[\w-]+)\s*:/g)) definedVars.add(m[1]);
};

// Definitions: build-time CSS plus every component's <style> block, plus the
// custom properties declared as inline style attributes.
for (const file of readdirSync(generated)) {
  if (file.endsWith(".css")) collectDefinitions(readFileSync(join(generated, file), "utf8"));
}
walk(src, (path) => {
  const text = readFileSync(path, "utf8");
  if (path.endsWith(".css")) return collectDefinitions(text);
  const style = text.match(/<style>([\s\S]*)<\/style>/);
  if (style) collectDefinitions(style[1]);
  for (const m of text.matchAll(/style:?--?([\w-]+)/g)) definedVars.add(`--${m[1]}`);
});

// Uses: the markup sections of every component. Style blocks are skipped —
// svelte-check already fails an unused CSS selector there.
walk(src, (path) => {
  if (!path.endsWith(".svelte") && !path.endsWith(".svelte.ts")) return;
  const text = readFileSync(path, "utf8");
  const markup = text.slice(
    text.indexOf("</script>") + 9,
    text.lastIndexOf("<style>") + 1 || undefined,
  );
  markup.split("\n").forEach((line, i) => {
    for (const m of line.matchAll(/class:([\w-]+)|class="([^"]*)"|var\((--[\w-]+)/g)) {
      const at = `${path}:${i + 1}`;
      if (m[3]) {
        if (!usedVars.has(m[3])) usedVars.set(m[3], at);
        continue;
      }
      const value = m[1] ?? m[2];
      for (const token of value.split(/\s+/)) {
        if (token && !token.includes("{") && !used.has(token)) used.set(token, at);
      }
    }
  });
});

const missing = [...used.entries()].filter(([token]) => !defined.has(token));
if (missing.length) {
  console.error(`Classes used but never defined:`);
  for (const [token, at] of missing) console.error(`  ${token}  (${at})`);
  process.exitCode = 1;
}

// A var built by interpolation (var(--color-{name})) yields a prefix; it is
// fine when some defined variable starts with it.
const prefixOk = (name) => [...definedVars].some((v) => v.startsWith(name));
const missingVars = [...usedVars.entries()].filter(
  ([name]) => !definedVars.has(name) && !prefixOk(name),
);
if (missingVars.length) {
  console.error(`Variables referenced but never defined:`);
  for (const [name, at] of missingVars) console.error(`  ${name}  (${at})`);
  process.exitCode = 1;
}

if (process.exitCode) process.exit(1);
console.log(`All ${used.size} classes and ${usedVars.size} variables in use are defined.`);
