#!/usr/bin/env python3
"""Check a same-project MR author against private CLA signatures."""

import csv
import io
import json
import os
import re
import sys
import urllib.error
import urllib.request

API = "https://code.eigin.ai/api/v4"
SIGNATURES = "projects/dev%2Finternal%2Fcla-signatures/repository/files/signatures.csv/raw?ref=main"
MARKER = "<!-- eigin-cla -->"
PHRASE = "I agree to the Eigin Individual CLA v1.0"
GUIDE = "https://docs.eigin.ai/contributing/contributor-agreement.html"
AGREEMENT = "https://docs.eigin.ai/contributing/individual-agreement.html"


class CheckError(Exception):
    """A sanitized, fail-closed checker error."""


class NoRedirect(urllib.request.HTTPRedirectHandler):
    """Prevent credentials from following HTTP redirects."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def request(path, token, body=None):
    """Call the fixed GitLab API without logging private response bodies."""
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(
        f"{API}/{path}", data=data,
        headers={"PRIVATE-TOKEN": token, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.build_opener(NoRedirect()).open(req, timeout=30) as response:
            return response.read().decode("utf-8"), response.headers
    except (urllib.error.URLError, OSError, UnicodeError, ValueError):
        raise CheckError("GitLab request failed.") from None


def decode(text):
    """Decode JSON with a public-safe failure message."""
    try:
        return json.loads(text)
    except (ValueError, TypeError):
        raise CheckError("Invalid GitLab response.") from None


def instructions(author):
    """Return the existing CLA bot comment unchanged."""
    return f"""{MARKER}
Thanks for contributing, @{author}! Before we can merge this, you need to sign our contributor license agreement. You only do this once.

1. Read the [individual agreement]({AGREEMENT}).
2. Reply on this merge request with this exact comment:

   ```text
   {PHRASE}
   ```

A maintainer will then record your signature, confirm here, and rerun the `cla` job. Contributing for a company? [Read this first]({GUIDE}#contributing-for-a-company).

cc @dev"""


def check(env, api=request):
    """Return zero for signed authors, one for unsigned authors; fail closed otherwise."""
    iid = env.get("BUILDKITE_PULL_REQUEST", "")
    commit = env.get("BUILDKITE_COMMIT", "")
    if not re.fullmatch(r"[1-9][0-9]*", iid) or not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise CheckError("Invalid MR build metadata.")
    read_token = env.get("CLA_READ_TOKEN", "")
    bot_token = env.get("CLA_BOT_TOKEN", "")
    if not read_token or not bot_token:
        raise CheckError("CLA credentials are missing.")
    path = f"projects/2/merge_requests/{iid}"
    mr = decode(api(path, bot_token)[0])
    if not isinstance(mr, dict) or any(mr.get(k) != v for k, v in {
        "iid": int(iid), "source_project_id": 2, "target_project_id": 2,
        "sha": commit, "state": "opened",
    }.items()):
        raise CheckError("MR identity or head does not match this build.")
    author = mr.get("author")
    if (not isinstance(author, dict) or type(author.get("id")) is not int
            or author["id"] <= 0 or not isinstance(author.get("username"), str)
            or not re.fullmatch(r"[A-Za-z0-9_.-]+", author["username"])):
        raise CheckError("Invalid MR author.")
    text = api(SIGNATURES, read_token)[0]
    try:
        rows = list(csv.reader(io.StringIO(text), strict=True))
    except csv.Error:
        raise CheckError("Invalid signature file.") from None
    if not rows or len(rows[0]) < 2:
        raise CheckError("Invalid signature file.")
    ids = []
    for row in rows[1:]:
        if not row:
            continue
        if len(row) != len(rows[0]) or not re.fullmatch(r"[1-9][0-9]*", row[0]):
            raise CheckError("Invalid signature file.")
        ids.append(int(row[0]))
    username = author["username"]
    if author["id"] in ids:
        print(f"@{username} has signed the contributor agreement.")
        return 0
    print(f"@{username} hasn't signed the contributor agreement yet.")
    print(f"Read {GUIDE}, then comment: {PHRASE}")
    page = 1
    for _ in range(100):
        text, headers = api(f"{path}/notes?per_page=100&page={page}", bot_token)
        notes = decode(text)
        if not isinstance(notes, list) or any(
            not isinstance(n, dict) or not isinstance(n.get("body"), str) for n in notes
        ):
            raise CheckError("Invalid MR notes response.")
        if any(MARKER in n["body"] for n in notes):
            return 1
        following = headers.get("X-Next-Page", "")
        if not following:
            break
        if not re.fullmatch(r"[1-9][0-9]*", following) or int(following) <= page:
            raise CheckError("Invalid MR notes pagination.")
        page = int(following)
    else:
        raise CheckError("MR notes pagination limit reached.")
    api(f"{path}/notes", bot_token, {"body": instructions(username)})
    print("Posted signing instructions on the merge request.")
    return 1


def main():
    """Run with sanitized diagnostics and no private API response logging."""
    try:
        return check(os.environ)
    except CheckError as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
