#!/usr/bin/env bash
# Exercise the packaged commands against an isolated local database.
set -euo pipefail
image=${1:?Pass the locally built portal image}
network="contributors-smoke-$$"
db="$network-db"
app="$network-app"
cleanup() {
  docker rm -fv "$app" "$db" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null
}
docker network create --internal "$network" >/dev/null
trap cleanup EXIT
docker run -d --name "$db" --network "$network" -e POSTGRES_PASSWORD=smoke postgres:16 >/dev/null
for _ in {1..60}; do
  docker exec "$db" pg_isready -h 127.0.0.1 -U postgres >/dev/null && break
  sleep 1
done
args=(--network "$network" -e "DATABASE_URL=postgresql://postgres:smoke@$db/postgres")
for script in migrate migrate prune-oauth-attempts; do
  docker run --rm "${args[@]}" "$image" node "scripts/$script.ts"
done
docker run -d --name "$app" "${args[@]}" -e ORIGIN=https://portal.invalid "$image" >/dev/null
for _ in {1..30}; do
  if docker exec "$app" node --input-type=module -e '
    for (const [path, expected] of [["/healthz", 200], ["/", 200], ["/calls/tool-safety", 200], ["/review/calls/tool-safety", 404]]) {
      if ((await fetch(`http://localhost:8080${path}`)).status !== expected) process.exit(1);
    }' 2>/dev/null; then exit 0; fi
  sleep 1
done
docker logs "$app" >&2
exit 1
