/**
 * Records what guardrails' interactive gates ask about, so recurring prompts
 * can be diagnosed (and converted into `allowedPaths` grants) without catching
 * the dialog on screen. Guardrails emits `guardrails:prompt:opened` for every
 * human-in-the-loop gate — path access, dangerous-command confirmation — with
 * feature, tool, and feature-specific metadata (for path access: the absolute
 * and display path).
 *
 * Event names are hardcoded with a pointer to guardrails' source rather than
 * imported: they're stable strings, and the import would pull half the package
 * for two constants.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export interface GatePromptLogEntry {
	/** ISO timestamp of when the gate asked. */
	time: string;
	/** Which guardrails feature opened the prompt (pathAccess, permissionGate, …). */
	feature: string;
	/** The tool whose call tripped the gate, when known. */
	tool: string;
	/** Display path for path-access prompts; the reason, otherwise. */
	detail: string;
}

const CAPACITY = 20;
const entries: GatePromptLogEntry[] = [];

/** The most recent gate prompts, oldest first. */
export function gatePromptLog(): readonly GatePromptLogEntry[] {
	return entries;
}

/** Add one entry, keeping the ring bounded. */
export function recordGatePrompt(entry: GatePromptLogEntry): void {
	entries.push(entry);
	if (entries.length > CAPACITY) entries.shift();
}

/** Subscribe to guardrails' prompt-opened events for the life of the session. */
export function recordGatePrompts(pi: ExtensionAPI): void {
	pi.events.on("guardrails:prompt:opened", (payload) => {
		const p = payload as {
			feature?: string;
			timestamp?: string;
			reason?: string;
			context?: { toolName?: string };
			prompt?: { metadata?: { displayPath?: string } };
		};
		recordGatePrompt({
			time: p.timestamp ?? new Date().toISOString(),
			feature: p.feature ?? "unknown",
			tool: p.context?.toolName ?? "unknown",
			detail: p.prompt?.metadata?.displayPath ?? p.reason,
		});
	});
}
