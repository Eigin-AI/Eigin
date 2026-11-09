#!/usr/bin/env bash
# Host-side Docker orchestration; test containers never receive the Docker socket.
set -euo pipefail
source .buildkite/scripts/linux-images.sh
component=${1:?Expected relay, postgres, or sdk}
case "$component" in relay|postgres|sdk) ;; *) echo 'Unknown Linux component' >&2; exit 2 ;; esac
if [[ -r /proc/sys/kernel/random/uuid ]]; then
    suffix=$(cat /proc/sys/kernel/random/uuid)
else
    suffix=$(uuidgen)
fi
cache=${LINUX_CACHE_DIR:-/cache/eigin-linux-$component}
options=(--rm --name "eigin-test-$suffix"
    --volume "$PWD:/work" --workdir /work
    --volume "$cache:/ci-cache"
    --env CARGO_HOME=/ci-cache/cargo --env CARGO_TARGET_DIR=/ci-cache/target
    --env PYTHONDONTWRITEBYTECODE=1)
test_container="eigin-test-$suffix"
postgres_container="eigin-postgres-$suffix"
cleanup() {
    status=$?
    trap - EXIT
    docker rm --force "$test_container" >/dev/null 2>&1 || true
    if [[ $component == postgres ]]; then
        if [[ $status != 0 ]]; then docker logs "$postgres_container" >&2 || true; fi
        docker rm --force --volumes "$postgres_container" >/dev/null 2>&1 || true
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ $component == postgres ]]; then
    command -v timeout >/dev/null
    docker run --detach --name "$postgres_container" \
        --env POSTGRES_PASSWORD=postgres "$POSTGRES_IMAGE"
    ready=false
    deadline=$((SECONDS + 60))
    for ((attempt=0; attempt<60 && SECONDS<deadline; attempt++)); do
        remaining=$((deadline - SECONDS))
        if ((remaining <= 0)); then break; fi
        if timeout --signal=KILL "${remaining}s" docker exec "$postgres_container" \
            pg_isready -h 127.0.0.1 -U postgres -q -t 1; then
            ready=true
            break
        fi
        sleep 1
    done
    if [[ $ready != true ]]; then echo 'Postgres readiness timed out' >&2; exit 1; fi
    options+=(--network "container:$postgres_container"
        --env DATABASE_URL=postgres://postgres:postgres@localhost/postgres
        --env POOL_TEST_DATABASE_URL=postgres://postgres:postgres@localhost/postgres)
fi
docker run "${options[@]}" "$RUST_IMAGE" \
    python3 .buildkite/scripts/check-linux.py "$component"
