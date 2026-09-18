Git policy: you may `git commit` and `git push` the current worktree branch to share and test your work. Never force-push (`--force`/`-f`/`--force-with-lease`), and never run history-rewriting or integrating git (merge, rebase, reset) or branch/remote mutations — those are the user's to run. 

`main` is a protected branch (no direct or force push; merge via MR only), so push worktree branches, not main. 

Also always blocked: `terraform apply`/`destroy` and `just infra deploy` (which wraps it) — discuss them or say what to try.
