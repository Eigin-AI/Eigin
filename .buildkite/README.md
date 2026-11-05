# Buildkite CI

One `eigin` pipeline runs on the hosted Linux AMD64 queue `linux-small`.
GitLab requires its external status to pass before merging.

| Step | Runs on | Purpose |
| --- | --- | --- |
| Versions | Main and same-repository MRs | Version checks and version/release integration tests |
| CI regression tests | Accepted builds | Python script tests; required before publishing |
| CLA | Same-repository MRs | Verify signatures and post signing instructions |
| Publish docs | Main webhook builds without an MR | Build and publish after Versions and CI tests pass |

## Provider setup

- Repository: `https://code.eigin.ai/dev/eigin.git`; default branch: `main`.
- Use the GitLab Self-Managed provider for `https://code.eigin.ai` and the project's
  Buildkite integration. Enable push/MR events and commit statuses.
- Enable branch and MR-head builds; limit branch builds to `main`.
- Disable tags, forks, and merged-results builds.
- Set this pipeline-level filter:

  ```text
  build.pull_request.id == null || (build.branch != "main" && build.pull_request.repository == pipeline.repository)
  ```

Pipeline settings bootstrap:

```yaml
steps:
  - label: ":pipeline: Upload"
    agents:
      queue: linux-small
    command: buildkite-agent pipeline upload
```

## Access and secrets

Only maintainers may push same-repository MR branches, edit pipeline settings,
or create builds. Treat branch-writing automation credentials as maintainer
credentials. Keep external contributors on forks; do not grant Developer access
under this model. MR code can access both CLA tokens.

Store credentials directly in cluster secrets. Never log tokens or signature data.

| Secret | Scope |
| --- | --- |
| `CLA_READ_TOKEN` | Signatures-project Reporter token with `read_api` |
| `CLA_BOT_TOKEN` | Eigin-project Reporter token with `api`; no signatures-project access |
| `DOCS_GITLAB_TOKEN` | Eigin-project Developer token with `api` for Secure Files |
| `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION` | Docs publisher credentials |

CLA secret policy (supports rebuilds):

```yaml
- pipeline_slug: "eigin"
```

Docs/font/AWS secret policy:

```yaml
- pipeline_id: "<eigin-pipeline-uuid>"
  build_branch: "main"
  build_source: "webhook"
```

Keep main-source MRs excluded: secret policies cannot distinguish them from main
pushes. Record token expirations and owners. After recording a CLA signature,
retry the checker for the current MR head; stale heads fail closed.

## Scripts and cache

CI scripts use Python's standard library. The full `rust:1-bookworm` image supplies
Python 3 through its Debian base; no per-job Python or pip installation is needed.
Archive extraction validates paths and links using APIs available in Python 3.11.
Cargo, curl, mdBook, and AWS CLI remain external tools.

Versions uses the `versions-v1` hosted cache volume for Cargo downloads, compiled
output, and the verified Node archive. Only Versions restores it; docs and CLA
run without this cache. Volume names are not access controls. Never mount this
cache in a production credential-bearing job.

Cache storage is best effort. Successful jobs save a snapshot; cold builds remain
supported. Node 22.23.4 and `just` 1.59.0 are checksum-pinned. Phase timings distinguish
installation, compilation, and tests. Rust tracks `rust:1-bookworm`.

```sh
python3 -m unittest discover -s .buildkite/tests
cargo test --locked --manifest-path tools/Cargo.toml --test docs_generate
```

For publishing operations, see [Docs releases](../docs/src/runbooks/docs-deployment.md).
