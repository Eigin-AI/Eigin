use anyhow::{Context, Result};
use serde_json::Value;
use std::collections::HashMap;
use std::fs;
use walkdir::WalkDir;

#[derive(Clone, Debug)]
pub struct FontFeature {
    pub tag: String,
    pub value: i64,
}

pub struct InstalledFonts {
    /// PostScript name maps keyed by fontFamily name, then weight name.
    families: HashMap<String, HashMap<String, String>>,
    scales: HashMap<String, f64>,
    /// OpenType feature settings keyed by fontFamily name.
    features: HashMap<String, Vec<FontFeature>>,
    pub file_names: Vec<String>,
}

impl InstalledFonts {
    pub fn postscript_name(&self, family: &str, weight: &str) -> Option<&str> {
        self.families
            .get(family)
            .and_then(|m| m.get(weight))
            .map(String::as_str)
    }

    pub fn scale(&self, family: &str) -> f64 {
        self.scales.get(family).copied().unwrap_or(1.0)
    }

    pub fn family_features(&self, family: &str) -> &[FontFeature] {
        self.features.get(family).map(Vec::as_slice).unwrap_or(&[])
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
        .context("tokens.json: missing 'fontFamily' group")?
        .as_object()
        .context("tokens.json: 'fontFamily' must be an object")?;

    let mut families = HashMap::new();
    let mut scales = HashMap::new();
    let mut features = HashMap::new();

    for (family_name, family_value) in family_group {
        families.insert(
            family_name.clone(),
            parse_weight_map(family_value, family_name)?,
        );
        scales.insert(family_name.clone(), parse_scale(family_value));
        features.insert(
            family_name.clone(),
            parse_features(family_value, family_name)?,
        );
    }

    Ok(Some(InstalledFonts {
        families,
        scales,
        features,
        file_names,
    }))
}

fn parse_weight_map(family_value: &Value, family_name: &str) -> Result<HashMap<String, String>> {
    let obj = family_value
        .as_object()
        .with_context(|| format!("fontFamily.{family_name}: expected object"))?;

    Ok(obj
        .iter()
        .filter_map(|(k, v)| v.as_str().map(|s| (k.clone(), s.to_string())))
        .collect())
}

fn parse_features(family_value: &Value, family_name: &str) -> Result<Vec<FontFeature>> {
    let Some(arr) = family_value.get("features") else {
        return Ok(Vec::new());
    };

    let mut out = Vec::new();
    for (i, entry) in arr
        .as_array()
        .with_context(|| format!("fontFamily.{family_name}.features: expected array"))?
        .iter()
        .enumerate()
    {
        let obj = entry
            .as_object()
            .with_context(|| format!("fontFamily.{family_name}.features[{i}]: expected object"))?;
        let tag = obj
            .get("tag")
            .and_then(Value::as_str)
            .with_context(|| {
                format!("fontFamily.{family_name}.features[{i}]: missing or non-string tag")
            })?
            .to_string();
        let value = obj
            .get("value")
            .and_then(Value::as_number)
            .and_then(|n| n.as_i64())
            .with_context(|| {
                format!("fontFamily.{family_name}.features[{i}]: missing or non-integer value")
            })?;
        out.push(FontFeature { tag, value });
    }
    Ok(out)
}

fn parse_scale(family_value: &Value) -> f64 {
    family_value
        .get("scale")
        .and_then(Value::as_f64)
        .unwrap_or(1.0)
}
