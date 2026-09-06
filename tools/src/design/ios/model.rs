use anyhow::{Context, Result};
use serde::Serialize;
use serde_json::Value;

use crate::codegen::ios::{fmt_cgfloat, hex_literal};
use crate::design::tokens::{
    ColorTree, SizingEntry, SizingScale, TYPOGRAPHY_FIELDS, parse_dimension, resolve_letter_spacing,
};

use super::fonts::InstalledFonts;
use super::swift_mappings::{
    swift_font_design, swift_font_weight, swift_text_style, swift_type_name,
    text_style_default_size,
};

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, Serialize)]
pub struct RadiusScale {
    pub entries: Vec<RadiusEntry>,
}

#[derive(Clone, Debug, Serialize)]
pub struct RadiusEntry {
    pub name: String,
    pub swift_value: String,
    pub description: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
pub struct TypographyScale {
    pub styles: Vec<TypographyStyle>,
}

#[derive(Clone, Debug, Serialize)]
pub struct TypographyStyle {
    pub name: String,
    pub font_expr: String,
    pub text_case: Option<String>,
    pub tracking: f64,
    pub line_spacing: Option<f64>,
    pub description: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
pub struct FontRegistrationInfo {
    pub file_names: Vec<String>,
    pub large_title_ps: String,
    pub inline_title_ps: String,
}

// ---------------------------------------------------------------------------
// Parse into typed models
// ---------------------------------------------------------------------------

pub fn parse_radius(tokens: &Value) -> Result<RadiusScale> {
    let group = tokens
        .get("radius")
        .with_context(|| "tokens.json: missing 'radius' group")?;

    let obj = group.as_object().context("radius group is not an object")?;
    let mut entries = Vec::new();
    for (name, token) in obj {
        let raw = token
            .get("$value")
            .and_then(Value::as_str)
            .with_context(|| format!("radius.{name}: missing string $value"))?;

        let swift_value = if name == "full" {
            ".infinity".to_string()
        } else {
            let pts = parse_dimension(raw)
                .with_context(|| format!("radius.{name}: invalid dimension '{raw}'"))?;
            fmt_cgfloat(pts)
        };

        entries.push(RadiusEntry {
            name: name.clone(),
            swift_value,
            description: token
                .get("$description")
                .and_then(Value::as_str)
                .map(String::from),
        });
    }
    Ok(RadiusScale { entries })
}

pub fn parse_typography(tokens: &Value, fonts: Option<&InstalledFonts>) -> Result<TypographyScale> {
    let group = tokens
        .get("typography")
        .with_context(|| "tokens.json: missing 'typography' group")?;

    let mut styles = Vec::new();
    for name in TYPOGRAPHY_FIELDS {
        let token = group
            .get(name)
            .with_context(|| format!("tokens.json: missing typography.{name}"))?;
        let value = token
            .get("$value")
            .with_context(|| format!("typography.{name}: missing $value"))?;

        let font_weight = value
            .get("fontWeight")
            .and_then(Value::as_str)
            .with_context(|| format!("typography.{name}: missing fontWeight"))?;
        let font_family = value.get("fontFamily").and_then(Value::as_str);
        let text_case = value.get("textCase").and_then(Value::as_str);
        let letter_spacing = resolve_letter_spacing(tokens, value, name)?;
        let font_size = value.get("fontSize").and_then(Value::as_f64);
        let line_height = value.get("lineHeight").and_then(Value::as_f64);
        let line_spacing = line_height.and_then(|lh| font_size.map(|fs| (lh - fs).max(0.0)));

        let font_expr = build_font_expr(value, font_weight, font_family, fonts, name)?;

        styles.push(TypographyStyle {
            name: name.to_string(),
            font_expr,
            text_case: text_case.map(String::from),
            tracking: letter_spacing,
            line_spacing,
            description: token
                .get("$description")
                .and_then(Value::as_str)
                .map(String::from),
        });
    }
    Ok(TypographyScale { styles })
}

fn build_font_expr(
    value: &Value,
    font_weight: &str,
    font_family: Option<&str>,
    fonts: Option<&InstalledFonts>,
    token_name: &str,
) -> Result<String> {
    if let Some(font_size) = value.get("fontSize").and_then(Value::as_f64) {
        // Direct size path — prefer custom font, fall back to system.
        let postscript = font_family
            .zip(fonts)
            .and_then(|(family, f)| f.postscript_name(family, font_weight));
        match postscript {
            Some(ps) => {
                let size_str = fmt_cgfloat(font_size);
                let features = resolve_features(value, font_family, fonts);
                if features.is_empty() {
                    return Ok(format!(".custom(\"{}\", size: {})", ps, size_str));
                }
                return Ok(format!(
                    ".featuredFont(name: \"{}\", size: {}, features: [{}])",
                    ps,
                    size_str,
                    features.join(", ")
                ));
            }
            None => {
                let swift_weight = swift_font_weight(font_weight).with_context(|| {
                    format!("typography.{token_name}: unknown fontWeight '{font_weight}'")
                })?;
                return Ok(format!(
                    ".system(size: {}, weight: {swift_weight})",
                    fmt_cgfloat(font_size)
                ));
            }
        }
    }

    // Legacy textStyle path
    let text_style = value
        .get("textStyle")
        .and_then(Value::as_str)
        .with_context(|| format!("typography.{token_name}: missing textStyle or fontSize"))?;
    let font_design = value
        .get("fontDesign")
        .and_then(Value::as_str)
        .unwrap_or("default");

    let swift_style = swift_text_style(text_style)
        .with_context(|| format!("typography.{token_name}: unknown textStyle '{text_style}'"))?;
    let swift_weight = swift_font_weight(font_weight)
        .with_context(|| format!("typography.{token_name}: unknown fontWeight '{font_weight}'"))?;
    let swift_design = swift_font_design(font_design)
        .with_context(|| format!("typography.{token_name}: unknown fontDesign '{font_design}'"))?;

    let postscript = font_family
        .zip(fonts)
        .and_then(|(family, f)| f.postscript_name(family, font_weight));
    match postscript {
        Some(ps) => {
            let base = text_style_default_size(text_style).with_context(|| {
                format!("typography.{token_name}: unknown textStyle '{text_style}'")
            })?;
            let scale = font_family
                .and_then(|f| fonts.map(|i| i.scale(f)))
                .unwrap_or(1.0);
            let size = (base as f64 * scale).round() as u32;
            let features = resolve_features(value, font_family, fonts);
            if features.is_empty() {
                Ok(format!(".custom(\"{ps}\", size: {size})"))
            } else {
                Ok(format!(
                    ".featuredFont(name: \"{ps}\", size: {size}, features: [{}])",
                    features.join(", ")
                ))
            }
        }
        None => Ok(format!(
            ".system({swift_style}, design: {swift_design}, weight: {swift_weight})"
        )),
    }
}

fn resolve_features(
    value: &Value,
    font_family: Option<&str>,
    fonts: Option<&InstalledFonts>,
) -> Vec<String> {
    // Typography-level override?
    if let Some(arr) = value.get("fontFeatures").and_then(Value::as_array) {
        return arr
            .iter()
            .filter_map(|entry| {
                let obj = entry.as_object()?;
                let tag = obj.get("tag")?.as_str()?;
                let val = obj.get("value")?.as_number()?.as_i64()?;
                Some(format!("FontFeature(tag: \"{tag}\", value: {val})"))
            })
            .collect();
    }

    // Fall back to family-level features
    let Some(family) = font_family else {
        return Vec::new();
    };
    let Some(installed) = fonts else {
        return Vec::new();
    };
    installed
        .family_features(family)
        .iter()
        .map(|f| format!("FontFeature(tag: \"{}\", value: {})", f.tag, f.value))
        .collect()
}

pub fn build_font_registration(fonts: Option<&InstalledFonts>) -> Option<FontRegistrationInfo> {
    fonts.map(|installed| FontRegistrationInfo {
        file_names: installed.file_names.clone(),
        large_title_ps: installed
            .postscript_name("display", "bold")
            .unwrap_or("NorthEastCN-Bold")
            .to_string(),
        inline_title_ps: installed
            .postscript_name("display", "demibold")
            .unwrap_or("NorthEastCN-SemiBold")
            .to_string(),
    })
}

// ---------------------------------------------------------------------------
// Swift source rendering helpers (used by templates that can't recurse)
// ---------------------------------------------------------------------------

impl SizingScale {
    /// Renders the nested sizing entries as Swift `enum` / `static let` blocks.
    pub fn render_body(&self) -> String {
        self.entries
            .iter()
            .map(|e| e.render(1))
            .collect::<Vec<_>>()
            .join("")
    }
}

impl SizingEntry {
    fn render(&self, depth: usize) -> String {
        let indent = "    ".repeat(depth);
        match self {
            SizingEntry::Leaf { name, pts, .. } => {
                format!(
                    "{indent}static let {name}: CGFloat = {}\n",
                    fmt_cgfloat(*pts)
                )
            }
            SizingEntry::Group { name, children } => {
                let type_name = swift_type_name(name);
                let mut out = format!("{indent}enum {type_name} {{\n");
                for child in children {
                    out.push_str(&child.render(depth + 1));
                }
                out.push_str(&format!("{indent}}}\n"));
                out
            }
        }
    }
}

impl ColorTree {
    /// Renders the struct body for `ResolvedColors`. Nested groups become
    /// inner structs; each group gets a matching `let name: TypeName`.
    pub fn render_struct_body(&self) -> String {
        let mut out = String::new();
        // Children of the root "color" pseudo-node are emitted directly
        // at the top level of ResolvedColors (not wrapped in a `struct Color`).
        for child in &self.children {
            child.write_struct_body_lines(&mut out, 1);
        }
        out
    }

    fn write_struct_body_lines(&self, out: &mut String, depth: usize) {
        let indent = "    ".repeat(depth);
        if let Some(_leaf) = &self.leaf {
            out.push_str(&format!("{indent}let {}: Color\n", self.name));
        } else if !self.children.is_empty() {
            let type_name = swift_type_name(&self.name);
            out.push_str(&format!("{indent}struct {type_name} {{\n"));
            for child in &self.children {
                child.write_struct_body_lines(out, depth + 1);
            }
            out.push_str(&format!("{indent}}}\n"));
            out.push_str(&format!("{indent}let {}: {type_name}\n", self.name));
        }
    }

    /// Renders the `ResolvedColors` initializer body for `DefaultTheme`
    /// for the given mode (`"light"` or `"dark"`), starting at `depth`.
    pub fn render_init_body(&self, mode: &str, depth: usize) -> String {
        let mut out = String::new();
        for (i, child) in self.children.iter().enumerate() {
            let last = i == self.children.len() - 1;
            child.write_init_body_lines(&mut out, mode, depth, !last);
        }
        out
    }

    fn write_init_body_lines(&self, out: &mut String, mode: &str, depth: usize, add_comma: bool) {
        let indent = "    ".repeat(depth);
        if let Some(leaf) = &self.leaf {
            let hex = if mode == "dark" {
                &leaf.dark_hex
            } else {
                &leaf.light_hex
            };
            let line = format!("{indent}{}: Color(hex: {})", self.name, hex_literal(hex));
            if add_comma {
                out.push_str(&format!("{line},\n"));
            } else {
                out.push_str(&format!("{line}\n"));
            }
        } else if !self.children.is_empty() {
            out.push_str(&format!("{indent}{}: .init(\n", self.name));
            for (i, child) in self.children.iter().enumerate() {
                let last = i == self.children.len() - 1;
                child.write_init_body_lines(out, mode, depth + 1, !last);
            }
            let line = format!("{indent})");
            if add_comma {
                out.push_str(&format!("{line},\n"));
            } else {
                out.push_str(&format!("{line}\n"));
            }
        }
    }
}
