import exampleSpec from "../../../../../content/examples/schedule-follow-ups-from-a-conversation.md?raw";

/** Download the same public example used by the reading page. */
export function GET() {
  return new Response(exampleSpec, {
    headers: {
      "Content-Type": "text/markdown; charset=utf-8",
      "Content-Disposition": 'attachment; filename="schedule-follow-ups-from-a-conversation.md"',
      "X-Content-Type-Options": "nosniff",
    },
  });
}
