/**
 * Pure sanitizing for tool-call rendering: one physical terminal row per line.
 *
 * pi-tui counts control characters as zero-width and assumes every array
 * entry a component returns is exactly one terminal row, so an embedded `\n`
 * silently renders as several rows and corrupts the TUI's cursor/scroll
 * arithmetic — stale, duplicated tool blocks. The built-in `Text` splits on
 * newlines; custom compact renderers must do the same before truncating.
 */

/** Normalize CR/tabs/control chars, split into single-row lines. ANSI ESC
 * is preserved — theme styling embeds real escape sequences in every line. */
export function toRenderLines(line: string): string[] {
	return line
		.replace(/\r\n?/g, "\n")
		.replace(/\t/g, "   ")
		.replace(/[\x00-\x08\x0b-\x1a\x1c-\x1f\x7f]/g, "")
		.split("\n")
		.filter((l) => l !== "");
}

/** Multi-line strings collapse onto the first line with a count of the rest. */
export function collapseMultiline(s: string): { first: string; rest: number } {
	const lines = toRenderLines(s);
	return { first: lines[0] ?? "", rest: Math.max(0, lines.length - 1) };
}
