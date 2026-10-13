/** A single tool call shown in the chat feed. */
export interface ToolCall {
  id: string;
  /** Display name, already resolved from the tool registry. */
  name: string;
  status: ToolStatus;
  arguments?: string;
  result?: string;
}

/**
 * Where a call stands. Denied is a permission refused; declined is the person
 * saying not now to something the call needed, which is a choice, not a fault.
 */
export type ToolStatus =
  "executing" | "awaitingPermission" | "completed" | "denied" | "declined" | "error";

/** Suffix appended to the name, or null when the status speaks for itself. */
export function statusSuffix(status: ToolStatus): string | null {
  switch (status) {
    case "awaitingPermission":
      return "awaiting permission";
    case "denied":
      return "denied";
    case "declined":
      return "declined";
    case "error":
      return "failed";
    default:
      return null;
  }
}
