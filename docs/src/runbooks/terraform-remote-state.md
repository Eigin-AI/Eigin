# Terraform remote state

By default Terraform keeps its state locally: plaintext secrets on one machine,
no backup, no locking. This guide moves it to a private, versioned Scaleway
bucket.

Remote state is opt-in. Without a `backend.tf`, Terraform keeps using local
state and none of this applies.

Like any Terraform setup, there's one manual bootstrap step: create the bucket
that later deployments store their state in (step 1). After that, migration
copies your local state to the bucket — copied, not moved, so nothing is lost
until you remove the local copy in the last step.

## Prerequisites

- Terraform >= 1.10.
- Scaleway CLI configured (`scw init`) with rights to create projects, buckets,
  and IAM resources.

## 1. Create the state bucket

```sh
just infra bootstrap
```

This creates a dedicated project, a private and versioned bucket, and a scoped
IAM key, then prints the values you need next. The bucket name is generated for
you.

## 2. Save the credentials

Add the printed outputs to the repo-root `.env` (git-ignored):

```sh
TFSTATE_ACCESS_KEY=...
TFSTATE_SECRET_KEY=...
TFSTATE_REGION=fr-par
```

Then back up the bootstrap's local state (`infra/scaleway/bootstrap/`) somewhere
secure and remove the local copy — it holds the scoped secret key, which
shouldn't linger on your machine. You only need it again to change the bootstrap
infrastructure later (rare); restore it from the backup then.

## 3. Point Terraform at the bucket

```sh
cp infra/scaleway/backend.tf.example infra/scaleway/backend.tf
```

Set `bucket` to the name from step 1. `backend.tf` is git-ignored but holds no
secrets — just the bucket name and region. Share that name with your team (or
keep a copy of the file somewhere private) so everyone points at the same
backend; access still needs the `TFSTATE_*` key.

## 4. Migrate state to the bucket

```sh
just infra migrate
```

Terraform copies every workspace's local state into the bucket (it migrates all
workspaces at once). Answer `yes` when prompted. Your local state stays in place,
so this is safe to re-run.

## 5. Verify, then remove local state

Check each workspace reads cleanly from the bucket before deleting anything.
`just infra plan` selects the workspace, loads credentials, and should report no
changes — a clean plan means the remote state matches:

```sh
just infra plan staging
just infra plan production
```

Once both workspaces are good, delete the local state so it can't drift or leak:
remove the `terraform.tfstate.d/` directory and any `terraform.tfstate` and
`.tfstate.backup` files under `infra/scaleway/`.
