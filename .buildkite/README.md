# Buildkite CI

One `eigin` pipeline uses hosted `linux-small` and `macos-medium` queues.
GitLab requires its external status to pass before merging.
Main publishes docs automatically; application tests wait for approval.

| Step | Runs on | Purpose |
| --- | --- | --- |
| Versions | Main and same-repository MRs | Version checks and version/release integration tests |
| CI regression tests | Accepted builds | Python script tests; required before publishing |
| Select Linux tests | Approved main and same-repository MRs | Upload relay, Postgres, and SDK jobs |
| Relay tests | Selected builds | Locked Rust test suite |
| Relay Postgres integration | Selected builds | Ignored tests against disposable Postgres 16 |
| Rust SDK checks | Selected builds | Native/WASM builds, binding fixtures, clippy, rustfmt |
| CLA | Same-repository MRs | Verify signatures and post signing instructions |
| Publish docs | Main webhook builds without an MR | Build and publish after Versions and CI tests pass |
| Run application tests | Main | Approval after Versions and CI tests; docs remain independent |
| iOS simulator tests | Approved main and same-repository MRs | Certificate-free staging build/tests; logs and xcresult artifacts |

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

CI scripts use Python's standard library; pipeline-flow tests also use checksum-pinned PyYAML 6.0.3 (MIT), installed in a temporary directory by `check-ci.py`. The test runner supplies just 1.59.0 on Linux AMD64; other development hosts need just installed. The full `rust:1-bookworm` image supplies
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
python3 .buildkite/scripts/check-ci.py
cargo test --locked --manifest-path tools/Cargo.toml --test docs_generate
```

## Linux component checks

MR selection compares the merge base of the freshly fetched target branch with
`BUILDKITE_COMMIT`. This covers the whole MR, including changes from earlier
pushes. Deleted files and both sides of renames participate in selection.

| Changed paths | Checks |
| --- | --- |
| `src/eigin_relay/**` | Relay and Postgres |
| `src/eigin_sdk/**` | SDK |
| `.buildkite/**`, `tools/**`, `justfile`, root Cargo/toolchain configuration | All three |
| Unrelated docs, design, npm, website, iOS changes | None |

Missing history, target-fetch failure, or invalid comparison metadata runs all
three checks. Main currently always runs all three: Buildkite does not provide a
verified pre-push SHA in this setup. Comparing only the last commit could miss
earlier changes in a multi-commit push. No baseline API token or state store is
introduced. A no-op step records builds with no affected components.

The selector has a 5-minute timeout. Selected jobs run independently, each with
a 30-minute timeout and a concurrency limit of 2 per component across builds.
They use `linux-small` and request no secrets. Failures, including selector or
upload failures, fail the Buildkite build and its existing GitLab commit status.
Docs publication retains its existing dependencies; it does not wait for these
component checks.

`linux-images.sh` pins Rust 1.99.1 Bookworm and Postgres 16 Bookworm by immutable
image-index digest. SDK setup explicitly installs clippy, rustfmt, and the WASM
target. Playwright, Node, Apple bindings, web, and website tests are outside this
delivery; web/website coverage in #372 remains open. Binding expansion is #356.

Each job has a separate 20 GB hosted cache, `linux-<component>-rust-1-99-1-v1`,
mounted at `/cache/eigin-linux-<component>` for Cargo downloads and build output.
Required tools come from the image or explicit setup, even on warm caches.
Do not mount these writable branch caches in credential-bearing jobs.

Postgres uses a unique container and shares its network namespace with the test
container. No host port is published. Both `DATABASE_URL` and
`POOL_TEST_DATABASE_URL` point to localhost, satisfying the pool-recovery guard.
Readiness probes TCP with a 60-second deadline and a bounded Docker invocation.
Exit/signal traps remove containers and database volumes and retain test failures.
Forced runner termination relies on hosted job teardown. Test containers receive
no Docker socket; host Docker, Bash, Python in the image, and GNU `timeout` are
required. Cold runs need network access to Docker Hub and Rust registries.

Reproduce on a Linux Docker host from the repository root:

```sh
bash .buildkite/scripts/run-linux-tests.sh relay
bash .buildkite/scripts/run-linux-tests.sh postgres
bash .buildkite/scripts/run-linux-tests.sh sdk
python3 .buildkite/scripts/check-ci.py
```

The wrapper defaults to the documented `/cache` paths. Set `LINUX_CACHE_DIR` to
an absolute host directory or a Docker volume name for local execution. On macOS,
install GNU `timeout` (`brew install coreutils`); UUID generation uses `uuidgen`.
To match Buildkite's architecture on Apple Silicon, set
`DOCKER_DEFAULT_PLATFORM=linux/amd64` (compilation through emulation is slower).

```sh
DOCKER_DEFAULT_PLATFORM=linux/amd64 LINUX_CACHE_DIR=eigin-relay-check \
  bash .buildkite/scripts/run-linux-tests.sh relay
```

For a cold run, use an empty cache directory or a new volume name. For a warm run,
reuse it. Remove disposable verification volumes after testing. The local
`just test relay postgres` recipe currently
sets only `DATABASE_URL`; this CI wrapper also covers the pool-recovery suite.

Hosted acceptance checks: run all three suites with empty then warm caches,
exercise concurrent Postgres jobs, and confirm a failing component produces a
failed GitLab status that blocks merging. These operational checks require a
working Linux runner and the existing GitLab required-status configuration.

For publishing operations, see [Docs releases](../docs/src/runbooks/docs-deployment.md).

## iOS checks and main approval

Same-repository MRs run iOS tests automatically after Versions, CI tests, and CLA.
On main, **Run application tests** starts Linux and iOS tests for that commit.
Docs publish independently; the overall build stays pending until approval.

In **Settings → Builds**, enable **Cancel Intermediate Builds** and **Skip
Intermediate Builds**, both filtered to `!main`. Main builds remain available
for approval within Buildkite's retention limits.

### macOS setup

Use `macos-medium` with these tools and runtimes:

| Tool | Selection |
| --- | --- |
| Xcode | 26.2, build 17C52 |
| Simulator | iPhone 17 Pro, iOS 26.2; watchOS 26.2 installed |
| Rust / SwiftFormat | 1.99.1 / 0.64.5 |
| just / XcodeGen | 1.59.0 / 2.46.0, checksum-verified downloads |

The job runs `just test ios --verbose` with ad-hoc signing for Keychain access.
Certificates, provisioning profiles and licensed fonts are unnecessary.
Local recipe defaults stay unchanged; CI overrides use `IOS_TEST_*` variables.
Logs, summaries, resolved packages and xcresult archives are under `logs/ios-ci/`.
Test and reporting failures fail the build. Transitive Swift dependencies remain
partially unlocked.

### Cost controls

- 60-minute timeout; one macOS job at a time.
- Separate main/MR 30 GB caches, keyed by Xcode build, Rust and layout version.
- Cache Cargo outputs/downloads and Swift package checkouts/artifacts.
- Stable source paths and timestamps let Cargo reuse unchanged builds.
- Xcode DerivedData stays temporary; cold builds remain supported.
- Keep MR caches out of credential-bearing jobs.

After merge, verify docs publish while main waits for approval, then approve
application tests and confirm newer main builds preserve older approvals.
