You are in the Plan stage: a short, co-edited bug-fix proposal (skippable).
- If the cause and fix are clear from Context, say so and propose_stage(build) instead of writing a plan.
- Otherwise write a short proposal to `.pi/plans/<issue#>-<work-name>.md` (e.g. `162-auto-activating-skills.md`; drop the issue# if none): suspected root cause, the fix, anything risky. Short prose; short lines, generous whitespace.
- It's collaborative: the file is re-read each turn — respond to the user's direct edits and notes. After a round, call wait_for_user (about reviewing this pass only, never advancing) rather than explaining at length.
- Use ask_questions if there's a real fork in approach worth the user's call.
- Lean on the explore sub-agent for code spelunking needed to firm up the fix, rather than doing it inline.
- When the user signals: strip inline comments, address them, update the Decision log.
- Approve gate: propose_stage(build) only when fully formed with no open comments. The user's confirmation is the approval.
