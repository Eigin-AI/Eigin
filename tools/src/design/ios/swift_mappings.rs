use anyhow::Result;
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
