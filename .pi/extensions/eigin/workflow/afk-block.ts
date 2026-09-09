/**
 * AFK pre-empt for the guardrails permission gate — uses guardrails' *own*
 * detection, not a mirror.
 *
 * Guardrails' permission gate shows a confirm dialog for builtin-dangerous
 * commands (`rm -rf`, `sudo`, `dd of=`, …) and the user's `patterns` when
 * `requireConfirmation` is on. In AFK the UI is still present, so that dialog
 * would hang — guardrails only auto-blocks when there's no UI. Its
 * `autoDenyPatterns` (force-push, `terraform apply`, git merge/rebase/reset,
 * …) already hard-block with no dialog, so they never hang either way; only the
 * builtin/matcher-dangerous commands hang. `.pi/extensions/eigin` loads before
 * package extensions, so an eigin `tool_call` handler runs before guardrails'.
 * In AFK we ask guardrails' own `checkDangerousCommand` + the user's resolved
 * config whether a command would prompt, and block it ourselves before the
 * dialog opens. Session grants (`allowedPatterns`) are honored.
 *
 * `@aliou/pi-guardrails` isn't one of pi's bundled module aliases, so a bare
 * import won't resolve from a project-local extension. We resolve the installed
 * package under `.pi/npm/node_modules` (populated by `pi install` at startup,
 * before extensions load) and import its source entries by absolute path. The
 * transitive `@earendil-works/pi-tui` import resolves because pi bundles it.
 *
 * If guardrails is removed or its internals move, `loadGuardrails` returns
 * `unavailable` and we fall back to a maintained keyword list (below) as a
 * substring check — less precise than the structural parser, but still blocks
 * obviously dangerous commands rather than letting them through to a hang.
 * The list mirrors guardrails' exported `BUILTIN_KEYWORD_PATTERNS` and must be
 * kept in sync with it; it lives here because it's needed exactly when guardrails
 * can't be imported.
 */

import { pathToFileURL } from "node:url";
import { resolve } from "node:path";

interface GuardrailsConfig {
  enabled: boolean;
  features: { permissionGate: boolean };
  permissionGate: {
    patterns: Array<{ pattern: string; description?: string; regex?: boolean }>;
    useBuiltinMatchers: boolean;
    requireConfirmation: boolean;
    allowedPatterns: Array<{ pattern: string; regex?: boolean }>;
  };
}

interface CompiledPattern {
  test: (input: string) => boolean;
}

interface GuardrailsApi {
  load(): Promise<void>;
  getConfig(): GuardrailsConfig;
  checkDangerousCommand(input: {
    command: string;
    patterns: CompiledPattern[];
    useBuiltinMatchers: boolean;
    fallbackPatterns: Array<{ pattern: string; description?: string; regex?: boolean }>;
  }): { description: string; pattern: string } | undefined;
  compileCommandPatterns(
    configs: Array<{ pattern: string; regex?: boolean }>,
  ): CompiledPattern[];
}

/** What `guardrailsCheck` concluded about a command. */
type GuardrailsDecision =
  | { kind: "prompt"; reason: string } // would show a dialog — block it
  | { kind: "safe" } // present and said safe
  | { kind: "unavailable" }; // guardrails couldn't be loaded

let apiPromise: Promise<GuardrailsApi | null> | null = null;
let configLoaded = false;

async function loadGuardrails(projectDir: string): Promise<GuardrailsApi | null> {
  if (!apiPromise) {
    apiPromise = (async () => {
      try {
        const base = resolve(
          projectDir,
          ".pi/npm/node_modules/@aliou/pi-guardrails",
        );
        const configMod = await import(
          pathToFileURL(resolve(base, "src/shared/config/index.ts")).href
        );
        const commandsMod = await import(
          pathToFileURL(resolve(base, "src/core/commands/index.ts")).href
        );
        const configLoader = configMod.configLoader;
        const { checkDangerousCommand, compileCommandPatterns } = commandsMod;
        if (!configLoader || !checkDangerousCommand || !compileCommandPatterns) {
          return null;
        }
        return {
          load: () => configLoader.load(),
          getConfig: () => configLoader.getConfig(),
          checkDangerousCommand,
          compileCommandPatterns,
        };
      } catch {
        return null;
      }
    })();
  }
  return apiPromise;
}

async function guardrailsCheck(
  command: string,
  projectDir: string,
): Promise<GuardrailsDecision> {
  const api = await loadGuardrails(projectDir);
  if (!api) return { kind: "unavailable" };

  try {
    if (!configLoaded) {
      try {
        api.getConfig(); // guardrails' own extension loads at startup; usually ready.
      } catch {
        await api.load(); // Not yet — load ourselves. Idempotent disk read.
      }
      configLoaded = true;
    }
    const config = api.getConfig();
    if (!config.enabled || !config.features.permissionGate) return { kind: "safe" };
    const gate = config.permissionGate;
    if (!gate.requireConfirmation) return { kind: "safe" }; // Warns+allows — never hangs.

    // Honor the user's allow-list / session grants — guardrails would bypass too.
    const allowed = api.compileCommandPatterns(gate.allowedPatterns);
    if (allowed.some((p) => p.test(command))) return { kind: "safe" };

    const compiled = api.compileCommandPatterns(gate.patterns);
    const match = api.checkDangerousCommand({
      command,
      patterns: compiled,
      useBuiltinMatchers: gate.useBuiltinMatchers,
      fallbackPatterns: gate.patterns,
    });
    if (!match) return { kind: "safe" };
    return { kind: "prompt", reason: match.description };
  } catch {
    return { kind: "unavailable" }; // Treat a guardrails hiccup as unavailable → fallback.
  }
}

// --- Fallback: guardrails unavailable -------------------------------------
// Mirrors guardrails' exported `BUILTIN_KEYWORD_PATTERNS`
// (src/core/commands/dangerous.ts). Lives here — not imported — because the
// fallback runs exactly when guardrails can't be imported. Keep in sync if
// guardrails' defaults move.
const FALLBACK_DANGEROUS_KEYWORDS: readonly string[] = [
  "rm -rf",
  "sudo",
  "dd of=",
  "mkfs.",
  "chmod -R 777",
  "chown -R",
  "doas",
  "pkexec",
  "shred",
  "wipefs",
  "blkdiscard",
  "fdisk",
  "parted",
  "docker run --privileged",
];

/** Substring check over the fallback keyword set. Exported for testing. */
export function fallbackBlocked(command: string): { reason: string } | null {
  for (const keyword of FALLBACK_DANGEROUS_KEYWORDS) {
    if (command.includes(keyword)) {
      return { reason: `matches builtin-dangerous pattern "${keyword}" (fallback)` };
    }
  }
  return null;
}

/**
 * Returns a reason if `command` should be blocked in AFK because guardrails'
 * permission gate would otherwise prompt (and hang) on it. Uses guardrails'
 * own detection; falls back to a substring keyword check only if guardrails
 * can't be loaded. `null` means the command is safe to run unattended.
 */
export async function afkBlockedCommand(
  command: string,
  projectDir: string,
): Promise<{ reason: string } | null> {
  const decision = await guardrailsCheck(command, projectDir);
  if (decision.kind === "prompt") return { reason: decision.reason };
  if (decision.kind === "safe") return null;
  // Unavailable — guardrails not loaded. Fall back so a missing install never
  // lets an obviously-dangerous command through to a hang.
  return fallbackBlocked(command);
}
