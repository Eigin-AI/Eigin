//! Platform-neutral design token parsing.
//!
//! Everything here is independent of the consuming platform: it loads
//! `design/tokens.json` and resolves it into plain values. Platform modules
//! (`ios/`, `web/`) layer their own naming and rendering on top.

use anyhow::{Context, Result};
use serde::Serialize;
use serde_json::Value;
use std::fs;

/// Canonical spacing scale order.
///
/// Tokens are listed in the visual order they appear on screen (ascending
/// size) rather than alphabetically so the generated file reads as a
/// logical progression. When adding a token to design/tokens.json, add the
/// key here too — tokens present in tokens.json but absent from this list are
/// silently skipped by codegen.
pub const SPACING_FIELDS: &[&str] = &[
    "n2", "n4", "n8", "n12", "n16", "n20", "n24", "n28", "n32", "n40", "n48", "n56", "n64", "n72",
    "n80", "n88", "n128",
];

/// Canonical motion speed tiers, fastest first.
pub const MOTION_FIELDS: &[&str] = &["fast", "normal", "slow"];

/// Canonical easing curve names, mirroring the iOS animation presets.
pub const MOTION_EASING_FIELDS: &[&str] = &["smooth", "snap", "gentle"];

/// Canonical typography scale order.
///
/// Tokens follow the visual hierarchy used in the design system rather than
/// alphabetical order so the generated file reads top-down from headlines down
/// to caption text. When adding a token to design/tokens.json, add the
/// key here too.
pub const TYPOGRAPHY_FIELDS: &[&str] = &[
    "display",
    "titleXl",
    "titleL",
    "titleM",
    "titleS",
    "titleXS",
    "authorL",
    "authorS",
    "standfirst",
    "body",
    "code",
    "chatMessage",
    "chatMessageUser",
    "button",
    "buttonSmall",
    "buttonLarge",
    "navTab",
    "tag",
    "miniLabel",
    "note",
    "description",
    "descriptionSmall",
    "descriptionExpo",
];

pub const GRID_BREAKPOINTS: &[(&str, &str, &str)] = &[
    ("mobile", "mobile", "Mobile width — iPhone (Figma: mobile)."),
    ("tablet", "tablet", "Tablet width — iPad (Figma: tablet)."),
    (
        "desktop",
        "desktop",
        "Desktop width — large iPad / desktop (Figma: desktop).",
    ),
];

// ---------------------------------------------------------------------------
// Loading and resolution
// ---------------------------------------------------------------------------

pub fn load_tokens(repo_root: &str) -> Result<Value> {
    let tokens_path = format!("{repo_root}/design/tokens.json");
    let content =
        fs::read_to_string(&tokens_path).with_context(|| format!("reading {tokens_path}"))?;
    serde_json::from_str(&content).context("parsing design/tokens.json")
}

/// Converts a `"42px"` string into an `f64` value.
pub fn parse_dimension(value: &str) -> Result<f64> {
    let trimmed = value.trim_end_matches("px");
    trimmed
        .parse::<f64>()
        .with_context(|| format!("not a valid px value: '{value}'"))
}

/// Resolves a DTCG alias (`{a.b.c}`) to a plain value for the given mode.
/// When `mode` is `"dark"` and the target token has a `$modes.dark` override,
/// that value is used instead of `$value`. Plain (non-reference) strings are
/// returned as-is. Bails after 16 hops to catch cycles.
pub fn resolve_alias<'a>(
    tokens: &'a Value,
    raw: &'a str,
    mode: &str,
    depth: u8,
) -> Result<&'a str> {
    if depth > 16 {
        anyhow::bail!("token ref cycle or excessive depth near '{raw}'");
    }
    let Some(path) = raw.strip_prefix('{').and_then(|s| s.strip_suffix('}')) else {
        return Ok(raw);
    };
    let mut node = tokens;
    for part in path.split('.') {
        node = node
            .get(part)
            .with_context(|| format!("token ref '{raw}': missing '{part}'"))?;
    }
    let value = if mode == "dark" {
        node.get("$modes")
            .and_then(|m| m.get("dark"))
            .and_then(Value::as_str)
            .or_else(|| node.get("$value").and_then(Value::as_str))
    } else {
        node.get("$value").and_then(Value::as_str)
    };
    let value = value.with_context(|| format!("token ref '{raw}': target has no string $value"))?;
    resolve_alias(tokens, value, mode, depth + 1)
}

/// Reads `letterSpacing` from a typography token value — either a named scale key
/// (e.g. `"s"`) resolved from `tokens.letterSpacing`, or a raw number.
pub fn resolve_letter_spacing(tokens: &Value, value: &Value, token_name: &str) -> Result<f64> {
    let raw = match value.get("letterSpacing") {
        None => return Ok(0.0),
        Some(v) => v,
    };
    if let Some(n) = raw.as_f64() {
        return Ok(n);
    }
    if let Some(key) = raw.as_str() {
        let dimension = tokens
            .get("letterSpacing")
            .and_then(|g| g.get(key))
            .and_then(|t| t.get("$value"))
            .and_then(Value::as_str)
            .with_context(|| {
                format!("typography.{token_name}: unknown letterSpacing key '{key}'")
            })?;
        return parse_dimension(dimension).with_context(|| {
            format!("typography.{token_name}: invalid letterSpacing dimension '{dimension}'")
        });
    }
    anyhow::bail!("typography.{token_name}: letterSpacing must be a number or a scale key string")
}

/// Returns true when a JSON node represents a DTCG color token.
pub fn is_color_token(node: &Value) -> bool {
    node.get("$type").and_then(Value::as_str) == Some("color")
}

// ---------------------------------------------------------------------------
// Typed models
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, Serialize)]
pub struct SpacingScale {
    pub entries: Vec<DimensionEntry>,
}

#[derive(Clone, Debug, Serialize)]
pub struct StrokeWeightScale {
    pub entries: Vec<DimensionEntry>,
}

#[derive(Clone, Debug, Serialize)]
pub struct DimensionEntry {
    pub name: String,
    pub pts: f64,
    pub description: Option<String>,
}

/// One named easing curve.
#[derive(Clone, Debug, Serialize)]
pub struct EasingEntry {
    pub name: String,
    pub points: [f64; 4],
    pub description: Option<String>,
}

/// One motion speed tier, in milliseconds.
#[derive(Clone, Debug, Serialize)]
pub struct DurationEntry {
    pub name: String,
    pub ms: f64,
    pub description: Option<String>,
}

#[derive(Clone, Debug, Serialize)]
pub struct SizingScale {
    pub entries: Vec<SizingEntry>,
}

#[derive(Clone, Debug, Serialize)]
pub enum SizingEntry {
    Leaf {
        name: String,
        pts: f64,
        /// Ratios and counts (`$type: number`) carry no unit; dimensions do.
        unitless: bool,
    },
    Group {
        name: String,
        children: Vec<SizingEntry>,
    },
}

#[derive(Clone, Debug, Serialize)]
pub struct GridScale {
    pub breakpoints: Vec<GridBreakpoint>,
}

#[derive(Clone, Debug, Serialize)]
pub struct GridBreakpoint {
    pub name: String,
    pub doc: String,
    pub columns: u64,
    pub outer: f64,
    pub inner: f64,
    pub gutter: f64,
}

#[derive(Clone, Debug, Serialize)]
pub struct ColorTree {
    pub name: String,
    pub children: Vec<ColorTree>,
    pub leaf: Option<ColorLeaf>,
}

#[derive(Clone, Debug, Serialize)]
pub struct ColorLeaf {
    pub light_hex: String,
    pub dark_hex: String,
}

// ---------------------------------------------------------------------------
// Parse into typed models
// ---------------------------------------------------------------------------

pub fn parse_spacing(tokens: &Value) -> Result<SpacingScale> {
    let group = tokens
        .get("spacing")
        .with_context(|| "tokens.json: missing 'spacing' group")?;

    let mut entries = Vec::new();
    for name in SPACING_FIELDS {
        let token = group
            .get(name)
            .with_context(|| format!("tokens.json: missing spacing.{name}"))?;
        let raw = token
            .get("$value")
            .and_then(Value::as_str)
            .with_context(|| format!("spacing.{name}: missing string $value"))?;
        let pts = parse_dimension(raw)
            .with_context(|| format!("spacing.{name}: invalid dimension '{raw}'"))?;
        entries.push(DimensionEntry {
            name: name.to_string(),
            pts,
            description: token
                .get("$description")
                .and_then(Value::as_str)
                .map(String::from),
        });
    }
    Ok(SpacingScale { entries })
}

/// Motion durations in milliseconds. Presets (springs, easing curves) stay
/// platform-level, so only the shared speed tiers live in tokens.
pub fn parse_motion(tokens: &Value) -> Result<Vec<DurationEntry>> {
    let group = tokens
        .get("motion")
        .with_context(|| "tokens.json: missing 'motion' group")?;

    let mut entries = Vec::new();
    for name in MOTION_FIELDS {
        let token = group
            .get(name)
            .with_context(|| format!("tokens.json: missing motion.{name}"))?;
        let raw = token
            .get("$value")
            .and_then(Value::as_str)
            .with_context(|| format!("motion.{name}: missing string $value"))?;
        let ms = parse_duration(raw)
            .with_context(|| format!("motion.{name}: invalid duration '{raw}'"))?;
        entries.push(DurationEntry {
            name: name.to_string(),
            ms,
            description: token
                .get("$description")
                .and_then(Value::as_str)
                .map(String::from),
        });
    }
    Ok(entries)
}

/// Named easing curves as cubic bezier control points.
pub fn parse_motion_easing(tokens: &Value) -> Result<Vec<EasingEntry>> {
    let group = tokens
        .get("motion")
        .and_then(|motion| motion.get("easing"))
        .with_context(|| "tokens.json: missing 'motion.easing' group")?;

    let mut entries = Vec::new();
    for name in MOTION_EASING_FIELDS {
        let token = group
            .get(name)
            .with_context(|| format!("tokens.json: missing motion.easing.{name}"))?;
        let raw = token
            .get("$value")
            .and_then(Value::as_array)
            .with_context(|| format!("motion.easing.{name}: $value must be an array"))?;
        let points: Vec<f64> = raw
            .iter()
            .map(|v| {
                v.as_f64().with_context(|| {
                    format!("motion.easing.{name}: control points must be numbers")
                })
            })
            .collect::<Result<_>>()?;
        let points: [f64; 4] = points
            .try_into()
            .map_err(|_| anyhow::anyhow!("motion.easing.{name}: expected four control points"))?;
        entries.push(EasingEntry {
            name: name.to_string(),
            points,
            description: token
                .get("$description")
                .and_then(Value::as_str)
                .map(String::from),
        });
    }
    Ok(entries)
}

/// Parses a `ms` duration value.
pub fn parse_duration(value: &str) -> Result<f64> {
    let trimmed = value.trim();
    let number = trimmed
        .strip_suffix("ms")
        .with_context(|| format!("duration '{value}' must end in ms"))?;
    number
        .trim()
        .parse::<f64>()
        .with_context(|| format!("duration '{value}' is not a number"))
}

pub fn parse_stroke_weight(tokens: &Value) -> Result<StrokeWeightScale> {
    let group = tokens
        .get("strokeWeight")
        .with_context(|| "tokens.json: missing 'strokeWeight' group")?;

    let obj = group
        .as_object()
        .context("strokeWeight group is not an object")?;
    let mut entries = Vec::new();
    for (name, token) in obj {
        let raw = token
            .get("$value")
            .and_then(Value::as_str)
            .with_context(|| format!("strokeWeight.{name}: missing string $value"))?;
        let pts = parse_dimension(raw)
            .with_context(|| format!("strokeWeight.{name}: invalid dimension '{raw}'"))?;
        entries.push(DimensionEntry {
            name: name.clone(),
            pts,
            description: token
                .get("$description")
                .and_then(Value::as_str)
                .map(String::from),
        });
    }
    Ok(StrokeWeightScale { entries })
}

pub fn parse_sizing(tokens: &Value) -> Result<SizingScale> {
    let group = tokens
        .get("sizing")
        .with_context(|| "tokens.json: missing 'sizing' group")?;
    let entries = parse_sizing_group(tokens, group)?;
    Ok(SizingScale { entries })
}

fn parse_sizing_group(tokens: &Value, node: &Value) -> Result<Vec<SizingEntry>> {
    let obj = node.as_object().context("sizing node is not an object")?;
    let mut entries = Vec::new();
    for (key, value) in obj {
        if key.starts_with('$') {
            continue;
        }
        let token_type = value.get("$type").and_then(Value::as_str);
        if token_type == Some("dimension") {
            let raw = value
                .get("$value")
                .and_then(Value::as_str)
                .with_context(|| format!("sizing token '{key}': missing $value"))?;
            let resolved = resolve_alias(tokens, raw, "light", 0)
                .with_context(|| format!("sizing token '{key}': alias resolution failed"))?;
            let pts = parse_dimension(resolved)
                .with_context(|| format!("sizing token '{key}': invalid dimension '{resolved}'"))?;
            entries.push(SizingEntry::Leaf {
                name: key.clone(),
                pts,
                unitless: false,
            });
        } else if token_type == Some("number") {
            let raw = value
                .get("$value")
                .and_then(Value::as_f64)
                .with_context(|| format!("sizing token '{key}': number $value must be numeric"))?;
            entries.push(SizingEntry::Leaf {
                name: key.clone(),
                pts: raw,
                unitless: true,
            });
        } else {
            let children = parse_sizing_group(tokens, value)?;
            entries.push(SizingEntry::Group {
                name: key.clone(),
                children,
            });
        }
    }
    Ok(entries)
}

pub fn parse_grid(tokens: &Value) -> Result<GridScale> {
    let group = tokens
        .get("grid")
        .with_context(|| "tokens.json: missing 'grid' group")?;

    let mut breakpoints = Vec::new();
    for (token_key, name, doc) in GRID_BREAKPOINTS {
        let bp = group
            .get(token_key)
            .with_context(|| format!("tokens.json: missing grid.{token_key}"))?;

        let columns = bp
            .get("columns")
            .and_then(|t| t.get("$value"))
            .and_then(Value::as_u64)
            .with_context(|| format!("grid.{token_key}.columns: missing integer $value"))?;

        let outer = parse_grid_dimension(bp, token_key, "outer")?;
        let inner = parse_grid_dimension(bp, token_key, "inner")?;
        let gutter = parse_grid_dimension(bp, token_key, "gutter")?;

        breakpoints.push(GridBreakpoint {
            name: name.to_string(),
            doc: doc.to_string(),
            columns,
            outer,
            inner,
            gutter,
        });
    }
    Ok(GridScale { breakpoints })
}

pub fn parse_color_tree(tokens: &Value) -> Result<ColorTree> {
    let group = tokens
        .get("color")
        .with_context(|| "tokens.json: missing 'color' group")?;
    let children = parse_color_subtree(tokens, group)?;
    Ok(ColorTree {
        name: "color".to_string(),
        children,
        leaf: None,
    })
}

fn parse_color_subtree(tokens: &Value, node: &Value) -> Result<Vec<ColorTree>> {
    let obj = node.as_object().context("color node is not an object")?;
    let mut entries = Vec::new();
    for (key, value) in obj {
        if key.starts_with('$') {
            continue;
        }
        if is_color_token(value) {
            let light_raw = value
                .get("$value")
                .and_then(Value::as_str)
                .with_context(|| format!("color.{key}: missing $value"))?;
            let dark_raw = value
                .get("$modes")
                .and_then(|m| m.get("dark"))
                .and_then(Value::as_str)
                .unwrap_or(light_raw);

            let light_hex = resolve_alias(tokens, light_raw, "light", 0)
                .with_context(|| format!("resolving color.{key} in light mode"))?;
            let dark_hex = resolve_alias(tokens, dark_raw, "dark", 0)
                .with_context(|| format!("resolving color.{key} in dark mode"))?;

            entries.push(ColorTree {
                name: key.clone(),
                children: vec![],
                leaf: Some(ColorLeaf {
                    light_hex: light_hex.to_string(),
                    dark_hex: dark_hex.to_string(),
                }),
            });
        } else {
            let children = parse_color_subtree(tokens, value)?;
            entries.push(ColorTree {
                name: key.clone(),
                children,
                leaf: None,
            });
        }
    }
    Ok(entries)
}

fn parse_grid_dimension(bp: &Value, bp_key: &str, field: &str) -> Result<f64> {
    let raw = bp
        .get(field)
        .and_then(|t| t.get("$value"))
        .and_then(Value::as_str)
        .with_context(|| format!("grid.{bp_key}.{field}: missing string $value"))?;
    parse_dimension(raw)
        .with_context(|| format!("grid.{bp_key}.{field}: invalid dimension '{raw}'"))
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parse_dimension_px() {
        assert_eq!(parse_dimension("42px").unwrap(), 42.0);
    }

    #[test]
    fn parse_dimension_raw_number() {
        assert_eq!(parse_dimension("12.5").unwrap(), 12.5);
    }

    #[test]
    fn parse_dimension_invalid() {
        assert!(parse_dimension("abc").is_err());
    }

    #[test]
    fn resolve_alias_plain_value() {
        let tokens = json!({ "spacing": { "n4": { "$value": "4px" } } });
        assert_eq!(resolve_alias(&tokens, "4px", "light", 0).unwrap(), "4px");
    }

    #[test]
    fn resolve_alias_reference() {
        let tokens = json!({ "color": { "primary": { "$value": "#FF0000" } } });
        assert_eq!(
            resolve_alias(&tokens, "{color.primary}", "light", 0).unwrap(),
            "#FF0000"
        );
    }

    #[test]
    fn resolve_alias_nested_reference() {
        let tokens = json!({ "core": { "red": { "$value": "#FF0000" } }, "alias": { "$value": "{core.red}" } });
        assert_eq!(
            resolve_alias(&tokens, "{alias}", "light", 0).unwrap(),
            "#FF0000"
        );
    }

    #[test]
    fn resolve_alias_dark_mode_override() {
        let tokens = json!({ "bg": { "$value": "#FFFFFF", "$modes": { "dark": "#000000" } } });
        assert_eq!(
            resolve_alias(&tokens, "{bg}", "dark", 0).unwrap(),
            "#000000"
        );
    }

    #[test]
    fn resolve_alias_cycle_detection() {
        let tokens = json!({ "a": { "$value": "{b}" }, "b": { "$value": "{a}" } });
        assert!(resolve_alias(&tokens, "{a}", "light", 0).is_err());
    }

    #[test]
    fn is_color_token_positive() {
        assert!(is_color_token(
            &json!({ "$type": "color", "$value": "#FF0000" })
        ));
    }

    #[test]
    fn is_color_token_negative() {
        assert!(!is_color_token(
            &json!({ "$type": "dimension", "$value": "4px" })
        ));
    }

    #[test]
    fn parse_spacing_follows_field_order() {
        let tokens = json!({ "spacing": { "n4": { "$value": "4px" }, "n8": { "$value": "8px" } } });
        assert!(parse_spacing(&tokens).is_err()); // missing the other fields
    }

    #[test]
    fn parse_sizing_resolves_aliases() {
        let tokens = json!({
            "spacing": { "n8": { "$value": "8px" } },
            "sizing": { "gap": { "$type": "dimension", "$value": "{spacing.n8}" } }
        });
        let scale = parse_sizing(&tokens).unwrap();
        assert!(
            matches!(&scale.entries[0], SizingEntry::Leaf { name, pts, .. } if name == "gap" && *pts == 8.0)
        );
    }

    #[test]
    fn parse_color_tree_resolves_modes() {
        let tokens = json!({
            "palette": { "neutral": { "100": { "$type": "color", "$value": "#FFFFFF",
                "$modes": { "dark": "#000000" } } } },
            "color": { "surface": {
                "base": { "$type": "color", "$value": "{palette.neutral.100}" }
            } }
        });
        let tree = parse_color_tree(&tokens).unwrap();
        let leaf = &tree.children[0].children[0];
        let leaf = leaf.leaf.as_ref().unwrap();
        assert_eq!(leaf.light_hex, "#FFFFFF");
        assert_eq!(leaf.dark_hex, "#000000");
    }

    #[test]
    fn parse_grid_reads_all_breakpoints() {
        let tokens = json!({
            "grid": {
                "mobile": { "columns": { "$type": "number", "$value": 2 },
                    "outer": { "$type": "dimension", "$value": "8px" },
                    "inner": { "$type": "dimension", "$value": "32px" },
                    "gutter": { "$type": "dimension", "$value": "16px" } }
            }
        });
        assert!(parse_grid(&tokens).is_err()); // tablet & desktop missing
    }
}
