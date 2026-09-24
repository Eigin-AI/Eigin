#!/bin/sh
# Fails when the merge request author hasn't signed the contributor agreement.
# Signatures live in the private dev/internal/cla-signatures project, read with the CI job token.
# When CLA_BOT_TOKEN is set, it also comments signing instructions once, mentioning maintainers
# so they're notified when the author replies to sign.
set -eu

signatures_project="dev%2Finternal%2Fcla-signatures"
phrase="I agree to the Eigin Individual CLA v1.0"
guide="https://docs.eigin.ai/contributing/contributor-agreement.html"
agreement="https://docs.eigin.ai/contributing/individual-agreement.html"
maintainers="@dev"
marker="<!-- eigin-cla -->"
mr_url="$CI_API_V4_URL/projects/$CI_MERGE_REQUEST_PROJECT_ID/merge_requests/$CI_MERGE_REQUEST_IID"

api() {
    curl --silent --show-error --fail --header "JOB-TOKEN: $CI_JOB_TOKEN" "$CI_API_V4_URL/$1"
}

# Calls the API as the CLA bot. Usage: bot <method> <url> [json body]
bot() {
    curl --silent --show-error --fail --request "$1" --header "PRIVATE-TOKEN: $CLA_BOT_TOKEN" \
        --header "Content-Type: application/json" ${3:+--data "$3"} "$2"
}

mr=$(api "projects/$CI_MERGE_REQUEST_PROJECT_ID/merge_requests/$CI_MERGE_REQUEST_IID")
author_id=$(printf "%s" "$mr" | jq -r '.author.id')
author=$(printf "%s" "$mr" | jq -r '.author.username')

signatures=$(api "projects/$signatures_project/repository/files/signatures.csv/raw?ref=main")

if printf "%s\n" "$signatures" | awk -F, -v id="$author_id" 'NR > 1 && $1 == id { found = 1 } END { exit !found }'; then
    echo "@$author has signed the contributor agreement."
    exit 0
fi

echo "@$author hasn't signed the contributor agreement yet."
echo
echo "To sign, read the agreement at $guide"
echo "then comment this exact text on the merge request:"
echo
echo "    $phrase"
echo
echo "A maintainer will record your signature, confirm on the merge request, and rerun this job."

if [ -z "${CLA_BOT_TOKEN:-}" ]; then
    exit 1
fi

if bot GET "$mr_url/notes?per_page=100" | jq -e --arg marker "$marker" 'any(.[]; .body | contains($marker))' > /dev/null; then
    exit 1
fi

body="$marker
Thanks for contributing, @$author! Before we can merge this, you need to sign our contributor license agreement. You only do this once.

1. Read the [individual agreement]($agreement).
2. Reply on this merge request with this exact comment:

   \`\`\`text
   $phrase
   \`\`\`

A maintainer will then record your signature, confirm here, and rerun the \`cla\` job. Contributing for a company? [Read this first]($guide#contributing-for-a-company).

cc $maintainers"

bot POST "$mr_url/notes" "$(jq -n --arg body "$body" '{body: $body}')" > /dev/null
echo "Posted signing instructions on the merge request."
exit 1
