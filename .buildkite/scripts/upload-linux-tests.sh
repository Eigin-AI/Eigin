#!/usr/bin/env bash
# Fetch with the runner's checkout credentials; only a validated SHA enters Docker.
set -euo pipefail
source .buildkite/scripts/linux-images.sh
export LINUX_DIFF_TARGET=''
if [[ ${BUILDKITE_PULL_REQUEST:-false} != false && -n ${BUILDKITE_PULL_REQUEST:-} ]]; then
    base=${BUILDKITE_PULL_REQUEST_BASE_BRANCH:-}
    if [[ -n $base ]] && git check-ref-format "refs/heads/$base" && \
        git fetch --no-tags origin "refs/heads/$base"; then
        LINUX_DIFF_TARGET=$(git rev-parse --verify 'FETCH_HEAD^{commit}')
    else
        echo 'Target fetch unavailable; all Linux checks will run.' >&2
    fi
fi
pipeline=$(mktemp)
trap 'rm -f "$pipeline"' EXIT
docker run --rm --volume "$PWD:/work:ro" --workdir /work \
    --env LINUX_DIFF_TARGET --env BUILDKITE_COMMIT --env BUILDKITE_PULL_REQUEST \
    --env PYTHONDONTWRITEBYTECODE=1 \
    "$RUST_IMAGE" python3 .buildkite/scripts/select-linux-tests.py > "$pipeline"
buildkite-agent pipeline upload "$pipeline"
