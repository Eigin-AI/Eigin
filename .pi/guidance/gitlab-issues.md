# GitLab issues — house style

How issues are written on dev/eigin (code.eigin.ai). The templates in `.gitlab/issue_templates/` cover quick bug reports and feature requests. Calibrate length and tone against this example: `.pi/guidance/issue-example.md`.

## Before writing

- Search existing issues (`glab issue list --search "..."`, `--output json`) — don't duplicate.
- One issue per discrete piece. A multi-part effort becomes several linked issues, not one mega-issue.
- Log the problem, not the conversation history. An issue should be readable by someone (or some agent) on a fresh day with no context.

## Titles

- One line. A plain sentence, not a label prefix or "Fix:".
- Bug → the symptom: "Frame hitches when knowledge tools are used".
- Feature/improvement/chore → the action: "Implement scalable skill retrieval", "Remove PendingDestination migration".

## Body

- Start with `## Problem`, always. What's wrong or missing, who/what it affects, why it matters. A couple of short paragraphs at most.
- Then only the structure the issue's kind calls for:
  - **Feature** → `## Proposal` with subsections when it has layers, alternatives, or what-it-replaces.
  - **Bug** → expected vs. actual, ordered steps to reproduce, suspected area, impact.
  - **Chore/decision** → `## Proposed solution`, plus `### Additional context` when there's history worth one line.
  - **Investigation** → `## To investigate`: numbered unknowns, not a fake solution.
- Testable work gets `## Done when` with observable criteria — "shuffled model list still starts onboarding on the best-ranked model", not "routing works".
- Tight prose, easy to parse. Plain English. Short sentences. Lists over paragraphs. Bold only for a claim the reader must not miss.
- Cross-reference related work as `#123` (issues), `!160` (MRs). Link research (arXiv, docs) inline.
- Write for closure. MRs open with `Closes #<n>` (see `.gitlab/merge_request_templates/Default.md`), so phrase the title and Problem so that sentence reads true when the fix lands — "Onboarding picks the first enabled model instead of the top-ranked model" closes cleanly; "Random onboarding thoughts" doesn't. The issue is the record of the problem; the MR is the record of the change — don't pre-write the solution into the issue unless the issue is the decision (feature/chore proposals say "Proposed", as above).

## Labels

- Exactly one type label where it applies: `bug`, `feature`, `improvement`, `idea`.
- Exactly one priority: `priority::urgent` / `high` / `medium` / `low`. Use `priority::medium` when in doubt.
- Domain labels when they genuinely apply: `ux`, `infra`, `security`, `compliance`, `performance`, … Check `glab label list` for what exists.
- Create with:
  ```
  glab issue create --title "..." --description "$(cat <path>)" --label "improvement,priority::medium"
  ```
  Draft the body to a file first — don't pass long prose on the command line.
