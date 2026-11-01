//! Bundle the pinned font files into the docs source assets.
use anyhow::{Context, Result, ensure};
use sha2::{Digest, Sha256};
use std::{collections::BTreeMap, fs, path::Path};
use walkdir::WalkDir;

/// Copy verified local fonts into the assets mdBook includes in its output.
pub fn bundle_fonts(root: &str) -> Result<()> {
    let root = Path::new(root);
    let manifest: BTreeMap<String, String> =
        serde_json::from_slice(&fs::read(root.join("docs/fonts.json"))?)?;
    ensure!(!manifest.is_empty(), "Docs font manifest is empty");
    let source = root.join("design/assets/fonts");
    let files = WalkDir::new(&source)
        .into_iter()
        .collect::<std::result::Result<Vec<_>, _>>()?;
    let mut assets = Vec::new();
    for (name, checksum) in manifest {
        ensure!(
            Path::new(&name).file_name().and_then(|s| s.to_str()) == Some(&name)
                && matches!(
                    Path::new(&name).extension().and_then(|s| s.to_str()),
                    Some("otf" | "ttf")
                ),
            "Invalid docs font filename: {name}"
        );
        let matches: Vec<_> = files
            .iter()
            .filter(|entry| {
                entry.file_type().is_file()
                    && entry
                        .file_name()
                        .to_string_lossy()
                        .replace(" copy.otf", ".otf")
                        == name
            })
            .collect();
        ensure!(
            matches.len() == 1,
            "Expected one source for {name} in design/assets/fonts, found {}. See docs/src/runbooks/docs-deployment.md",
            matches.len()
        );
        let bytes = fs::read(matches[0].path())?;
        ensure!(
            !bytes.is_empty() && hex::encode(Sha256::digest(&bytes)) == checksum,
            "Docs font checksum mismatch: {name}"
        );
        assets.push((name, bytes));
    }
    let notice = fs::read(root.join("LICENSES/FiraCode-LICENSE.txt"))
        .context("reading Fira Code licence notice")?;
    let destination = root.join("docs/src/fonts");
    if destination.exists() {
        fs::remove_dir_all(&destination)?;
    }
    fs::create_dir_all(&destination)?;
    for (name, bytes) in assets {
        fs::write(destination.join(&name), bytes)
            .with_context(|| format!("bundling docs font {name}"))?;
    }
    fs::write(destination.join("FiraCode-LICENSE.txt"), notice)?;
    Ok(())
}
