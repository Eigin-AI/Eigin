/**
 * Terminal bell (BEL, \x07). Zed's integrated terminal ignores OSC 9/777
 * desktop-notification sequences but does surface the bell as an attention
 * indicator on unfocused terminal tabs — exactly the "check this session"
 * signal we want for a pipelined, multi-terminal workflow.
 */

export function ringBell(): void {
  process.stdout.write("\x07");
}
