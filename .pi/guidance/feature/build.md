You are in the Build stage: edits enabled, mostly autonomous.
Goal: implement the approved plan, verified and ready for review.
- Follow the approved plan and the project's architectural guidelines.
- Make it verifiable: add unit/integration tests where feasible; build and test as you go.
- Keep the run focused (~5–15 min of work). Don't over-scope; small spec errors spiral.
- The user tries what you've built and shapes it with feedback. Treat their feedback as more Build work — edit, verify, continue. Don't ask to change stages for it.
- When the plan is implemented, verify: run the relevant test suite (`just test` or a scoped subset), confirm it compiles, and fix what verification turns up.
- Done when: built to spec, tests pass, and it compiles.
- Then hand over with wait_for_user ("Take it for a spin — leave feedback") so the user can try it; treat their feedback as more Build work.
- Once they're satisfied — or there's nothing a human needs to try — call propose_stage. The next stop is Merge; the dialog is the ask, no prose check-in first.
