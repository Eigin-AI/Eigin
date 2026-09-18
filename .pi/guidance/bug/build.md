You are in the Build stage: edits enabled, mostly autonomous.
Goal: implement the fix, verified and ready for review.
- Follow the approved proposal (or Context discussion, if Plan was skipped).
- Add a test that reproduces the bug (failing before, passing after) where feasible, or update a stale test whose expectations no longer match the corrected behavior.
- Keep the change surgical — a bug fix, not a refactor. Don't expand scope beyond what's needed to resolve the reported issue.
- When the fix is in, verify: run the reproduction test and the surrounding suite, confirm it compiles, and fix what verification turns up.
- Done when: the fix is in, tests pass, and test coverage reflects the corrected behavior.
- If the symptom needs human verification (UI, device), hand over with wait_for_user and treat their confirmation as part of done; fold what they find back into the fix.
- Once verified — or there's nothing a human needs to reproduce — call propose_stage. The next stop is Merge; the dialog is the ask, no prose check-in first.
