//! Model-asset mirror tooling: upload a version tree to the asset bucket.
//!
//! `eigin-tools assets upload` walks a local directory (typically a
//! HuggingFace repo checked out at a pinned revision), computes per-file size +
//! SHA-256, writes a `manifest.json` into the tree, uploads everything under
//! `assets/{id}/{version}/` with create-only puts (version prefixes are
//! immutable), and prints the ready-to-paste `assets.toml` entry.
//!
//! The tool never fetches from HuggingFace — `--source-dir` is the sole
//! content input. `--origin-repo`/`--origin-rev` are optional provenance
//! metadata recorded in the manifest for audit.

use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, bail};
use clap::{Args, Subcommand};
use object_store::aws::AmazonS3Builder;
use object_store::path::Path as ObjectPath;
use object_store::{ObjectStore, ObjectStoreExt, PutMode, PutPayload, WriteMultipart};
use serde::Serialize;
use sha2::{Digest, Sha256};
use walkdir::WalkDir;

#[derive(Args)]
pub struct AssetsArgs {
    #[command(subcommand)]
    command: AssetsCommand,
}

#[derive(Subcommand)]
enum AssetsCommand {
    /// Upload a version tree to the asset mirror.
    Upload(UploadArgs),
}

#[derive(Args)]
pub struct UploadArgs {
    /// Stable asset identifier, e.g. gemma4-e2b. Never changes across versions.
    #[arg(long)]
    id: String,

    /// Local directory holding the asset files (the tree is mirrored 1:1).
    #[arg(long)]
    source_dir: PathBuf,

    /// Version id. Defaults to the upload-time UTC timestamp (YYYY-MM-DD-HHMM);
    /// pass explicitly only to reproduce a specific id.
    #[arg(long)]
    version: Option<String>,

    /// Upstream repository the tree came from (provenance metadata only).
    /// Recorded together with `--origin-rev`; supply both or neither.
    #[arg(long, requires = "origin_rev")]
    origin_repo: Option<String>,

    /// Upstream revision (commit sha) the tree came from (provenance metadata only).
    #[arg(long, requires = "origin_repo")]
    origin_rev: Option<String>,

    /// S3 endpoint, e.g. https://s3.fr-par.scw.cloud.
    #[arg(long)]
    endpoint: String,

    /// Bucket name.
    #[arg(long)]
    bucket: String,

    /// Bucket region, e.g. fr-par.
    #[arg(long)]
    region: String,

    /// Access key for the upload (write) identity.
    #[arg(long)]
    access_key: String,

    /// Secret key for the upload (write) identity.
    #[arg(long)]
    secret_key: String,
}

/// One file entry in the manifest.
#[derive(Serialize)]
struct ManifestFile {
    path: String,
    size: u64,
    sha256: String,
}

/// Upstream provenance, recorded for audit.
#[derive(Serialize)]
struct ManifestOrigin {
    repo: String,
    revision: String,
}

/// The manifest written as `assets/{id}/{version}/manifest.json`.
#[derive(Serialize)]
struct Manifest {
    asset_id: String,
    version: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    origin: Option<ManifestOrigin>,
    files: Vec<ManifestFile>,
}

pub fn run(args: AssetsArgs) -> Result<()> {
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .context("starting tokio runtime")?;
    match args.command {
        AssetsCommand::Upload(args) => runtime.block_on(upload(args)),
    }
}

async fn upload(args: UploadArgs) -> Result<()> {
    let version = args.version.clone().unwrap_or_else(default_version_id);
    let source = &args.source_dir;
    if !source.is_dir() {
        bail!("--source-dir {} is not a directory", source.display());
    }

    // 1. Walk the tree (1:1; a pre-existing manifest.json from a failed run is regenerated).
    println!(" indexing {}", source.display());
    let mut files: Vec<ManifestFile> = Vec::new();
    for entry in WalkDir::new(source)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_file())
    {
        let path = entry.path().strip_prefix(source).with_context(|| {
            format!("{} not under {}", entry.path().display(), source.display())
        })?;
        let path = path.to_string_lossy().replace('\\', "/");
        if path == "manifest.json" {
            continue;
        }
        // Skip hidden files and dirs (any dot-prefixed path component): the
        // `.cache/` metadata `hf download` leaves in the dir, `.DS_Store`,
        // `.gitattributes`, etc. They're never part of the asset.
        if path.split('/').any(|c| c.starts_with('.')) {
            continue;
        }
        let size = entry.metadata()?.len();
        let sha256 = sha256_file(entry.path())?;
        println!("  {path}  {size} bytes  {sha256:.16}…");
        files.push(ManifestFile { path, size, sha256 });
    }
    files.sort_unstable_by(|a, b| a.path.cmp(&b.path));
    if files.is_empty() {
        bail!("no files found under {}", source.display());
    }

    // 2. Build + write the manifest into the tree. Its own sha pins the whole listing.
    let manifest = Manifest {
        asset_id: args.id.clone(),
        version: version.clone(),
        origin: match (&args.origin_repo, &args.origin_rev) {
            (Some(repo), Some(rev)) => Some(ManifestOrigin {
                repo: repo.clone(),
                revision: rev.clone(),
            }),
            _ => None,
        },
        files,
    };
    let manifest_bytes = serde_json::to_vec_pretty(&manifest)?;
    let local_manifest = source.join("manifest.json");
    std::fs::write(&local_manifest, &manifest_bytes)
        .with_context(|| format!("writing {}", local_manifest.display()))?;
    let manifest_sha = hex::encode(Sha256::digest(&manifest_bytes));
    println!(
        " manifest.json: {} files, sha256 {manifest_sha:.16}… ({})",
        manifest.files.len(),
        version
    );

    // 3. Upload: large files via multipart (streamed, no whole-file buffering or
    // single-request timeout), the small manifest via a create-only put. A
    // pre-existing object is skipped, so a partial run just resumes.
    let store = AmazonS3Builder::new()
        .with_endpoint(&args.endpoint)
        .with_bucket_name(&args.bucket)
        .with_region(&args.region)
        .with_access_key_id(&args.access_key)
        .with_secret_access_key(&args.secret_key)
        .with_allow_http(false)
        .build()
        .context("building S3 client")?;

    println!(" uploading to {}/{}/{}", args.bucket, args.id, version);
    let manifest_key = ObjectPath::from(format!("assets/{}/{}/manifest.json", args.id, version));
    let mut uploaded = 0usize;
    let mut skipped = 0usize;

    // Files first, manifest last, so a partial run never leaves a live manifest
    // pointing at absent files.
    for file in &manifest.files {
        let key = ObjectPath::from(format!("assets/{}/{}/{}", args.id, version, file.path));
        if skip_existing(&store, &key).await? {
            skipped += 1;
            continue;
        }
        upload_multipart(&store, &key, &source.join(&file.path))
            .await
            .with_context(|| format!("uploading {}", file.path))?;
        uploaded += 1;
    }
    if skip_existing(&store, &manifest_key).await? {
        skipped += 1;
    } else {
        store
            .put_opts(
                &manifest_key,
                PutPayload::from(manifest_bytes),
                object_store::PutOptions::from(PutMode::Create),
            )
            .await
            .context("uploading manifest.json")?;
        uploaded += 1;
    }
    println!(" uploaded {uploaded}, skipped {skipped} (already present)");

    // 4. Print the ready-to-paste assets.toml entry.
    println!();
    println!("[[assets]]");
    println!("id = \"{}\"", args.id);
    println!("version = \"{version}\"");
    println!("manifest_sha256 = \"{manifest_sha}\"");
    Ok(())
}

/// HEAD the object; skip it if already present (partial-failure rerun).
async fn skip_existing(store: &object_store::aws::AmazonS3, key: &ObjectPath) -> Result<bool> {
    match store.head(key).await {
        Ok(_) => Ok(true),
        Err(object_store::Error::NotFound { .. }) => Ok(false),
        Err(e) => Err(e.into()),
    }
}

/// Stream a file to object storage as a multipart upload: bounded memory and
/// per-part requests, so multi-GB files don't buffer whole or trip the
/// single-request timeout.
async fn upload_multipart(
    store: &object_store::aws::AmazonS3,
    key: &ObjectPath,
    path: &Path,
) -> Result<()> {
    use std::io::Read;

    let mut file = std::fs::File::open(path)?;
    let upload = store.put_multipart(key).await?;
    let mut writer = WriteMultipart::new(upload);
    let mut buf = vec![0u8; 8 * 1024 * 1024];
    loop {
        let n = file.read(&mut buf)?;
        if n == 0 {
            break;
        }
        // Bound in-flight parts so a fast disk can't outrun the network.
        writer.wait_for_capacity(4).await?;
        writer.write(&buf[..n]);
    }
    writer.finish().await?;
    Ok(())
}

/// Version id from the current UTC time: `YYYY-MM-DD-HHMM`. Unique per upload
/// without suffixes; date sort order preserved.
fn default_version_id() -> String {
    let secs = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0) as i64;
    // Civil-time conversion (Howard Hinnant's algorithm) — no chrono dep.
    let days = secs.div_euclid(86_400);
    let secs_of_day = secs.rem_euclid(86_400);
    let (year, month, day) = civil_from_days(days);
    let hour = secs_of_day / 3600;
    let minute = (secs_of_day % 3600) / 60;
    format!("{year:04}-{month:02}-{day:02}-{hour:02}{minute:02}")
}

fn civil_from_days(z: i64) -> (i64, u32, u32) {
    let z = z + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = (doy - (153 * mp + 2) / 5 + 1) as u32;
    let m = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
    (if m <= 2 { y + 1 } else { y }, m, d)
}

fn sha256_file(path: &Path) -> Result<String> {
    let mut file = std::fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buf = vec![0u8; 1024 * 1024];
    loop {
        let n = std::io::Read::read(&mut file, &mut buf)?;
        if n == 0 {
            break;
        }
        hasher.update(&buf[..n]);
    }
    Ok(hex::encode(hasher.finalize()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_id_shape() {
        let v = default_version_id();
        assert_eq!(v.len(), 15, "expected YYYY-MM-DD-HHMM, got {v}");
        assert_eq!(v.as_bytes()[10], b'-');
        assert!(v[11..].chars().all(|c| c.is_ascii_digit()), "{v}");
    }

    #[test]
    fn civil_from_days_known_date() {
        // 2026-01-15 UTC is day 20468 since the epoch.
        let (y, m, d) = civil_from_days(20_468);
        assert_eq!((y, m, d), (2026, 1, 15));
    }
}
