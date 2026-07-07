/**
 * Project-scoped defaults for third-party tools.
 *
 * Some installed packages (e.g. pi-web-access) only read configuration from a
 * global, user-scoped file (`~/.pi/web-search.json`), with no project-local
 * override. To get repo-specific defaults without touching the user's global
 * config, we patch the tool call's input directly via the `tool_call` event
 * — the same mechanism used for guardrails.
 */

export interface ToolCallInput {
	[key: string]: unknown;
}

const WEB_SEARCH_TOOL = "web_search";
const WEB_SEARCH_DEFAULT_WORKFLOW = "auto-summary";

/**
 * Apply Eigin's project default for web_search: skip the browser curator and
 * return a model-generated summary instead, unless the caller already
 * specified a workflow explicitly.
 */
export function applyWebSearchDefault(toolName: string, input: ToolCallInput): void {
	if (toolName !== WEB_SEARCH_TOOL) return;
	if (input.workflow !== undefined) return; // Caller was explicit; respect it.
	input.workflow = WEB_SEARCH_DEFAULT_WORKFLOW;
}

const SUBAGENT_TOOL = "subagent";

/**
 * Apply Eigin's project defaults for the subagent tool: find project-local
 * agents (our committed `.pi/agents/explore.md`) and skip the per-call
 * confirmation prompt for them. The vendored tool's own default scope is
 * user-only and its own default is to confirm project agents — sane for an
 * untrusted repo, but our project agents are committed, reviewed, and this
 * repo is already trusted, so the prompt would just be friction on every call.
 */
export function applySubagentDefaults(toolName: string, input: ToolCallInput): void {
	if (toolName !== SUBAGENT_TOOL) return;
	if (input.agentScope === undefined) input.agentScope = "both";
	if (input.confirmProjectAgents === undefined) input.confirmProjectAgents = false;
}
