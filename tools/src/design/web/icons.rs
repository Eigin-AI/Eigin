//! Web icons: the SVG tree as a typed `icons.ts`, keyed by its repo-relative
//! path. Icon names mirror `design/assets/icons/` structure, same as the iOS
//! `Iconography` enum. Ink colors are normalized to `currentColor` so icons
//! tint with the icon color tokens.

use anyhow::{Context, Result};
use std::collections::BTreeMap;
use std::fmt::Write;
use std::fs;
use std::path::{Path, PathBuf};

pub fn render(repo_root: &str, header: &str) -> Result<String> {
    let source_dir = PathBuf::from(repo_root).join("design/assets/icons");
    let mut files: BTreeMap<String, PathBuf> = BTreeMap::new();
    if source_dir.exists() {
        collect(&source_dir, &source_dir, &mut files)?;
    }

    let mut out = String::from(header);
    out.push_str("// Add SVGs to design/assets/icons/, not this file.\n");
    out.push_str("// Ink fills/strokes are normalized to currentColor at generation time.\n\n");

    out.push_str("export type IconName =\n");
    for name in files.keys() {
        let _ = writeln!(out, "  | \"{name}\"");
    }
    out.push_str("\nexport const icons: Record<IconName, string> = {\n");
    for (name, path) in &files {
        let svg =
            fs::read_to_string(path).with_context(|| format!("reading icon {}", path.display()))?;
        let svg = rewrite_attr(&rewrite_attr(&svg, "fill"), "stroke");
        let _ = writeln!(out, "  \"{name}\": {},", serde_json::to_string(&svg)?);
    }
    out.push_str("};\n");
    Ok(out)
}

/// Rewrite every attribute value to `currentColor`, except `none` (kept for
/// stroke-based icons that must draw outlines, not filled silhouettes).
fn rewrite_attr(svg: &str, attr: &str) -> String {
    let needle = format!("{attr}=\"");
    let mut out = String::with_capacity(svg.len());
    let mut rest = svg;
    while let Some(start) = rest.find(&needle) {
        let value_start = start + needle.len();
        let Some(len) = rest[value_start..].find('"') else {
            break;
        };
        out.push_str(&rest[..value_start]);
        let value = &rest[value_start..value_start + len];
        if value == "none" {
            out.push_str(value);
        } else {
            out.push_str("currentColor");
        }
        rest = &rest[value_start + len..];
    }
    out.push_str(rest);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_ink_to_current_color() {
        let svg = "<svg fill=\"none\"><path fill=\"#1E1E1D\" stroke=\"#000000\"/></svg>";
        assert_eq!(
            rewrite_attr(&rewrite_attr(svg, "fill"), "stroke"),
            "<svg fill=\"none\"><path fill=\"currentColor\" stroke=\"currentColor\"/></svg>"
        );
    }
}

fn collect(root: &Path, dir: &Path, files: &mut BTreeMap<String, PathBuf>) -> Result<()> {
    let entries = fs::read_dir(dir).with_context(|| format!("reading {}", dir.display()))?;
    for entry in entries {
        let path = entry
            .with_context(|| format!("reading entry in {}", dir.display()))?
            .path();
        if path.is_dir() {
            collect(root, &path, files)?;
        } else if path.extension().and_then(|s| s.to_str()) == Some("svg") {
            let name = path
                .strip_prefix(root)
                .unwrap()
                .with_extension("")
                .to_str()
                .context("non-utf8 icon path")?
                .replace(std::path::MAIN_SEPARATOR, "/");
            files.insert(name, path);
        }
    }
    Ok(())
}
