#!/usr/bin/env bash
# Print TF_VAR_* exports for the given environment.
# Usage (Makefile):   eval "$(scripts/tf-env.sh staging)"
# Usage (standalone): eval "$(scripts/tf-env.sh staging)" && terraform plan ...
set -euo pipefail
ENV="${1:-staging}"
ENV_UPPER=$(echo "$ENV" | tr 'a-z' 'A-Z')

cd "$(git rev-parse --show-toplevel)"
# shellcheck disable=SC1091
[ -f .env ] && set -a && . .env && set +a

relay_key_var="EIGIN_RELAY_KEY_${ENV_UPPER}"
mojeek_var="MOJEEK_API_KEY_${ENV_UPPER}"

cat <<EOF
export TF_VAR_eigin_relay_key="${!relay_key_var:-}"
export TF_VAR_mojeek_api_key="${!mojeek_var:-}"
export TF_VAR_scw_secret_key="$(scw config get secret-key 2>/dev/null || true)"
export TF_VAR_image_tag="$(git rev-parse --short HEAD)"
EOF
