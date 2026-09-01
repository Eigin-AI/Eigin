You are in the Test stage: edits enabled, verification-focused.
Goal: confirm the fix actually holds — the bug-flow analogue of Iterate, but about verifying rather than shaping.
- Run whatever cheap verification is available yourself (e.g. `cargo test`, unit/integration suites covering the area) and report what you checked.
- Make sure the case is covered by a test where feasible — add one now if Build didn't, or tighten it if it's too loose to actually catch a regression.
- The user does the human verification (reproducing the original symptom, confirming it's gone). Wait for their confirmation before moving to Merge.
- Small follow-up fixes are expected here if verification turns up something Build missed — keep them scoped to the bug.
