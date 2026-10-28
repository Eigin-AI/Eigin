# Website hosting

Production-only module in the shared Scaleway root, alongside relay. Creates a dedicated project, public static bucket, Edge Services Starter subscription/CDN and publisher identity.

## Operator requirements

| Tool | Version / installation |
| --- | --- |
| Terraform | >=1.10; [install](https://developer.hashicorp.com/terraform/install) |
| Scaleway CLI | [Install](https://www.scaleway.com/en/docs/scaleway-cli/quickstart/), authenticate with `scw init` |
| AWS CLI | v2; `brew install awscli` on macOS |
| curl | >=7.71; `brew install curl` if needed, with its binary on PATH |
| Node / npm | Node >=22.17, npm >=10 |
| Rust / just | Stable Rust via rustup; [development setup](../../../../docs/src/contributing/development-environment.md) |
| tar | BSD or GNU tar with gzip support |
| Docker | Running daemon for shared infrastructure deployment |

Use the existing [remote-state configuration](../../../../docs/src/runbooks/terraform-remote-state.md). Operators need shared production-state access, including relay secrets. Keep credentials local; publishing has no production CI credentials.

## Infrastructure

```sh
just infra plan production
just infra deploy production
```

These commands manage the whole root, including relay. Review the full plan. The root requires Scaleway provider 2.73 or newer within 2.x; review any lockfile upgrade. See [current Edge Services pricing](https://www.scaleway.com/en/pricing/network/) for subscription and traffic charges.

`website_domains` in `environments/production.tfvars` lists custom hostnames. An empty list serves the generated HTTPS endpoint only. Configured hostnames enable managed TLS; their DNS must route to this pipeline. See [Scaleway domain requirements](https://www.scaleway.com/en/docs/edge-services/how-to/configure-custom-domain/).

The project, bucket and pipeline have destruction protection. Review resource/module removal carefully.

## Publishing and credentials

Use `just release website`; see the [release runbook](../../../../docs/src/runbooks/website-deployment.md) for verification and recovery.

- Publishing reads named production outputs and uploads with a project-scoped `ObjectStorageFullAccess` key.
- Keys stay in memory and replace inherited AWS credentials for uploads. Keep unrelated storage out of the website project.
- Rotate `module.website[0].scaleway_iam_api_key.publisher` through a reviewed replacement before its one-year expiry.
- Serialize publishing and infrastructure changes; Terraform state locking does not serialize uploads.
- The generated endpoint remains available with custom domains and is used for release checks.
