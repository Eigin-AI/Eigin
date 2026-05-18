use anyhow::{Context, Result};
use serde_json::Value;

/// Converts a `"42px"` string into an `f64` value.
pub fn parse_dimension(value: &str) -> Result<f64> {
    let trimmed = value.trim_end_matches("px");
    trimmed
        .parse::<f64>()
        .with_context(|| format!("not a valid px value: '{value}'"))
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

/// Returns true when a JSON node represents a DTCG color token.
pub fn is_color_token(node: &Value) -> bool {
    node.get("$type").and_then(Value::as_str) == Some("color")
}

/// Capitalises the first letter to produce a Swift type name.
pub fn swift_type_name(name: &str) -> String {
    let mut chars = name.chars();
    match chars.next() {
        None => String::new(),
        Some(c) => c.to_uppercase().collect::<String>() + chars.as_str(),
    }
}

/// Maps design-system text style names to SwiftUI initializer tokens.
pub fn swift_text_style(style: &str) -> Result<&'static str> {
    Ok(match style {
        "largeTitle" => ".largeTitle",
        "title" => ".title",
        "title2" => ".title2",
        "title3" => ".title3",
        "headline" => ".headline",
        "subheadline" => ".subheadline",
        "body" => ".body",
        "callout" => ".callout",
        "footnote" => ".footnote",
        "caption" => ".caption",
        "caption2" => ".caption2",
        other => anyhow::bail!("unknown textStyle: '{other}'"),
    })
}

/// Default point sizes for each UIFontTextStyle at the Large (default)
/// Dynamic Type size.
pub fn text_style_default_size(style: &str) -> Result<u32> {
    Ok(match style {
        "largeTitle" => 34,
        "title" => 28,
        "title2" => 22,
        "title3" => 20,
        "headline" => 17,
        "subheadline" => 15,
        "body" => 17,
        "callout" => 16,
        "footnote" => 13,
        "caption" => 12,
        "caption2" => 11,
        other => anyhow::bail!("unknown textStyle: '{other}'"),
    })
}

/// Maps design-system weight names to the closest SwiftUI `Font.Weight`.
pub fn swift_font_weight(weight: &str) -> Result<&'static str> {
    Ok(match weight {
        "extralight" => ".ultraLight",
        "light" => ".light",
        "regular" => ".regular",
        "medium" => ".medium",
        "demibold" => ".semibold",
        "bold" => ".bold",
        "extrabold" => ".heavy",
        other => anyhow::bail!(
            "unknown fontWeight: '{other}' — use design system names: extralight, light, regular, medium, demibold, bold, extrabold"
        ),
    })
}

/// Maps design-system `fontDesign` names to SwiftUI `Font.Design`.
pub fn swift_font_design(design: &str) -> Result<&'static str> {
    Ok(match design {
        "default" => ".default",
        "serif" => ".serif",
        "rounded" => ".rounded",
        "monospaced" => ".monospaced",
        other => anyhow::bail!("unknown fontDesign: '{other}'"),
    })
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
    fn swift_type_name_capitalises() {
        assert_eq!(swift_type_name("border"), "Border");
    }

    #[test]
    fn swift_text_style_known() {
        assert_eq!(swift_text_style("body").unwrap(), ".body");
    }

    #[test]
    fn swift_text_style_unknown() {
        assert!(swift_text_style("unknown").is_err());
    }

    #[test]
    fn text_style_default_size_body() {
        assert_eq!(text_style_default_size("body").unwrap(), 17);
    }

    #[test]
    fn swift_font_weight_maps() {
        assert_eq!(swift_font_weight("bold").unwrap(), ".bold");
        assert_eq!(swift_font_weight("regular").unwrap(), ".regular");
    }

    #[test]
    fn swift_font_weight_unknown() {
        assert!(swift_font_weight("thin").is_err());
    }

    #[test]
    fn swift_font_design_known() {
        assert_eq!(swift_font_design("rounded").unwrap(), ".rounded");
    }
}
