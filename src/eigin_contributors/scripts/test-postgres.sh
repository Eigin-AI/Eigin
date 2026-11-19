#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

nonce=$(node -p 'require("node:crypto").randomBytes(16).toString("hex")')
database="contributors_test_$nonce"
username=contributors_test
container=$(docker run --rm -d -p 127.0.0.1::5432 \
    -e "POSTGRES_USER=$username" -e "POSTGRES_PASSWORD=$nonce" \
    -e "POSTGRES_DB=$database" postgres:16)
trap 'docker stop "$container" >/dev/null' EXIT
for ((attempt=0; attempt<60; attempt++)); do
    if docker exec "$container" pg_isready -h localhost -U "$username" -d "$database" -q; then break; fi
    sleep 1
done
if ((attempt == 60)); then echo 'Test PostgreSQL did not become ready.' >&2; exit 1; fi
address=$(docker port "$container" 5432/tcp)
export TEST_DATABASE_URL="postgresql://$username:$nonce@$address/$database"
DATABASE_URL="$TEST_DATABASE_URL" npm run db:migrate
npm run test
for suite in auth submissions review selection publication content e2e production; do
    npm run "test:$suite"
done
