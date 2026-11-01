#!/usr/bin/env bash
# Download only the docs fonts from this project's GitLab Secure Files.
set -euo pipefail
: "${CI_API_V4_URL:?Required}" "${CI_PROJECT_ID:?Required}" "${CI_JOB_TOKEN:?Required}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
api="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/secure_files"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
curl --fail --silent --show-error --proto '=https' \
    --header "JOB-TOKEN: ${CI_JOB_TOKEN}" "${api}?per_page=100" > "$work/files.json"
mkdir -p "$root/design/assets/fonts/docs"
while IFS=$'\t' read -r name checksum; do
    id="$(jq -er --arg name "$name" '[.[] | select(.name == $name)] | if length == 1 then .[0].id else error("Missing or duplicate Secure File: " + $name) end' "$work/files.json")"
    curl --fail --silent --show-error --proto '=https' \
        --header "JOB-TOKEN: ${CI_JOB_TOKEN}" "${api}/${id}/download" > "$work/font"
    actual="$(sha256sum "$work/font" | cut -d ' ' -f 1)"
    if [ "$actual" != "$checksum" ]; then
        echo "Docs font checksum mismatch: $name" >&2
        exit 1
    fi
    mv "$work/font" "$root/design/assets/fonts/docs/$name"
done < <(jq -r 'to_entries[] | [.key, .value] | @tsv' "$root/docs/fonts.json")
