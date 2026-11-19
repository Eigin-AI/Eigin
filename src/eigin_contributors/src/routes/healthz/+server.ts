/** Process readiness without waking the serverless database. */
export function GET() {
  return new Response("ok");
}
