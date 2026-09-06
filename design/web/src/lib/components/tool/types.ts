/** A single tool call shown in the chat feed. */
export interface ToolCall {
  id: string;
  /** Display name, already resolved from the tool registry. */
  name: string;
  status: ToolStatus;
  arguments?: string;
  result?: string;
}

export type ToolStatus = "executing" | "awaitingPermission" | "completed" | "denied" | "error";

/** Suffix appended to the name, or null when the status speaks for itself. */
export function statusSuffix(status: ToolStatus): string | null {
  switch (status) {
    case "awaitingPermission":
      return "awaiting permission";
    case "denied":
      return "denied";
    case "error":
      return "failed";
    default:
      return null;
  }
}
