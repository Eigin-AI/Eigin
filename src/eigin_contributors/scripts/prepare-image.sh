#!/usr/bin/env bash
# Prepare a credential-free build context for the Terraform Docker provider.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
npm ci
just generate web
# Derive the client update marker from emitted assets, independent of checkout history.
PORTAL_BUILD_VERSION=content just test contributor
version=$(cd src/eigin_contributors/build/client && find . -type f | LC_ALL=C sort | while IFS= read -r asset; do shasum -a 256 "$asset"; done | shasum -a 256 | cut -d' ' -f1)
PORTAL_BUILD_VERSION="$version" npm run build --workspace @eigin/contributors
portal=src/eigin_contributors
context=infra/scaleway/.contributor-image
mkdir -p "$context"
stage=$(mktemp -d "$context/.prepare.XXXXXX")
trap 'rm -rf "$stage"' EXIT
cp "$portal/Dockerfile" "$stage/Dockerfile"
for path in package.json package-lock.json design/web/package.json src/eigin_sdk/web/package.json \
  src/eigin_web/package.json src/eigin_website/package.json "$portal/package.json" "$portal/build" \
  "$portal/migrations" "$portal/scripts/migrate.ts" "$portal/scripts/prune-oauth-attempts.ts" \
  "$portal/src/lib/server/database.ts"; do
  mkdir -p "$stage/$(dirname "$path")"
  cp -R "$path" "$stage/$path"
done
rm -rf "$context/current"
mv "$stage" "$context/current"
