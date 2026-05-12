use anyhow::{Context, Result};
use serde_json::Value;
use std::collections::HashMap;
use std::fs;
use walkdir::WalkDir;

pub struct InstalledFonts {
    pub sans_serif: HashMap<String, String>,
    pub sans_serif_scale: f64,
    pub serif: HashMap<String, String>,
    pub serif_scale: f64,
    pub file_names: Vec<String>,
}

impl InstalledFonts {
    pub fn postscript_name(&self, family: &str, weight: &str) -> Option<&str> {
        match family {
            "sansSerif" => self.sans_serif.get(weight).map(String::as_str),
            "serif" => self.serif.get(weight).map(String::as_str),
            _ => None,
        }
    }

    pub fn scale(&self, family: &str) -> f64 {
        match family {
            "sansSerif" => self.sans_serif_scale,
            "serif" => self.serif_scale,
            _ => 1.0,
        }
    }
}

/// Checks `design/assets/fonts/` for OTF/TTF files. If any are present, copies
/// them into `Resources/Fonts/` and returns the PostScript name map from tokens.
/// Returns `None` when no font files are found (OSS / system-font path).
pub fn install(repo_root: &str, tokens: &Value) -> Result<Option<InstalledFonts>> {
    let source_dir = format!("{repo_root}/design/assets/fonts");
    let dest_dir = format!("{repo_root}/src/eigin_ios/Resources/Fonts");

    let font_files: Vec<_> = WalkDir::new(&source_dir)
        .into_iter()
        .filter_map(|e| e.ok())
        .map(|e| e.into_path())
        .filter(|p| {
            p.is_file()
                && p.extension()
                    .and_then(|e| e.to_str())
                    .map(|e| matches!(e, "otf" | "ttf"))
                    .unwrap_or(false)
        })
        .collect();

    if font_files.is_empty() {
        return Ok(None);
    }

    fs::create_dir_all(&dest_dir).with_context(|| format!("creating {dest_dir}"))?;

    let mut file_names = Vec::new();
    for path in &font_files {
        let filename = path.file_name().unwrap();
        let name = filename.to_string_lossy().into_owned();
        fs::copy(path, format!("{dest_dir}/{name}"))
            .with_context(|| format!("copying font {:?}", path))?;
        file_names.push(name);
    }
    file_names.sort();

    let family_group = tokens
        .get("fontFamily")
        .context("tokens.json: missing 'fontFamily' group")?;

    let sans_serif = parse_weight_map(family_group, "sansSerif")?;
    let sans_serif_scale = parse_scale(family_group, "sansSerif")?;
    let serif = parse_weight_map(family_group, "serif")?;
    let serif_scale = parse_scale(family_group, "serif")?;

    Ok(Some(InstalledFonts {
        sans_serif,
        sans_serif_scale,
        serif,
        serif_scale,
        file_names,
    }))
}

fn parse_weight_map(family_group: &Value, role: &str) -> Result<HashMap<String, String>> {
    let role_obj = family_group
        .get(role)
        .with_context(|| format!("fontFamily: missing '{role}'"))?
        .as_object()
        .with_context(|| format!("fontFamily.{role}: expected object"))?;

    Ok(role_obj
        .iter()
        .filter_map(|(k, v)| v.as_str().map(|s| (k.clone(), s.to_string())))
        .collect())
}

fn parse_scale(family_group: &Value, role: &str) -> Result<f64> {
    Ok(family_group
        .get(role)
        .and_then(|r| r.get("scale"))
        .and_then(Value::as_f64)
        .unwrap_or(1.0))
}
