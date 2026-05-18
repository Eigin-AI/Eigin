use convert_case::{Case, Casing};

/// Capitalises the first letter, kebab segments become boundaries.
pub fn pascal_case(name: &str) -> String {
    name.to_case(Case::Pascal)
}

/// Lower-camelCase: first segment stays lower, rest title-cased.
pub fn camel_case(name: &str) -> String {
    name.to_case(Case::Camel)
}

/// Wraps Swift keywords in backticks so they can be used as member names.
pub fn swift_ident_escape(ident: &str) -> String {
    match ident {
        "break" | "case" | "catch" | "continue" | "default" | "defer" | "do" | "else"
        | "fallthrough" | "for" | "guard" | "if" | "in" | "repeat" | "return" | "throw" | "try"
        | "where" | "while" | "class" | "deinit" | "enum" | "extension" | "func" | "import"
        | "init" | "inout" | "let" | "operator" | "protocol" | "struct" | "subscript"
        | "typealias" | "var" | "as" | "false" | "is" | "nil" | "self" | "Self" | "super"
        | "true" | "type" | "Type" | "private" | "fileprivate" | "internal" | "public" | "open"
        | "static" | "override" | "mutating" | "nonisolated" | "isolated" | "lazy" | "weak"
        | "unowned" | "inherited" => {
            format!("`{ident}`")
        }
        _ => ident.to_string(),
    }
}

/// Formats a CGFloat value cleanly — integers without decimal point, fractions trimmed.
pub fn fmt_cgfloat(v: f64) -> String {
    if v.fract() == 0.0 {
        format!("{}", v as i64)
    } else {
        let s = format!("{:.2}", v);
        s.trim_end_matches('0').trim_end_matches('.').to_string()
    }
}

/// Validates and returns a quoted hex string for `Color(hex:)`.
pub fn hex_literal(hex: &str) -> String {
    let clean = hex
        .trim_start_matches('#')
        .chars()
        .filter(|c| c.is_ascii_hexdigit())
        .collect::<String>();
    if clean.len() == 6 || clean.len() == 8 {
        format!("\"#{clean}\"")
    } else {
        format!("\"{hex}\"")
    }
}

use minijinja::Environment;

/// Registers all iOS-specific filters on a minijinja environment.
pub fn install_filters(env: &mut Environment) {
    env.add_filter("pascal_case", pascal_case);
    env.add_filter("camel_case", camel_case);
    env.add_filter("swift_ident_escape", swift_ident_escape);
    env.add_filter("fmt_cgfloat", fmt_cgfloat);
    env.add_filter("hex_literal", hex_literal);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pascal_case_kebab() {
        assert_eq!(pascal_case("hello-world"), "HelloWorld");
    }

    #[test]
    fn pascal_case_single() {
        assert_eq!(pascal_case("test"), "Test");
    }

    #[test]
    fn camel_case_kebab() {
        assert_eq!(camel_case("hello-world"), "helloWorld");
    }

    #[test]
    fn camel_case_single() {
        assert_eq!(camel_case("test"), "test");
    }

    #[test]
    fn swift_ident_escape_keywords() {
        assert_eq!(swift_ident_escape("default"), "`default`");
        assert_eq!(swift_ident_escape("enum"), "`enum`");
    }

    #[test]
    fn swift_ident_escape_normal() {
        assert_eq!(swift_ident_escape("hello"), "hello");
        assert_eq!(swift_ident_escape("world_1"), "world_1");
    }

    #[test]
    fn fmt_cgfloat_integer() {
        assert_eq!(fmt_cgfloat(42.0), "42");
    }

    #[test]
    fn fmt_cgfloat_fraction() {
        assert_eq!(fmt_cgfloat(42.5), "42.5");
    }

    #[test]
    fn fmt_cgfloat_trailing_zeros() {
        // 42.50 → "42.5"
        assert_eq!(fmt_cgfloat(42.5000), "42.5");
    }

    #[test]
    fn hex_literal_valid_six() {
        assert_eq!(hex_literal("#FF0000"), "\"#FF0000\"");
    }

    #[test]
    fn hex_literal_valid_eight() {
        assert_eq!(hex_literal("#FF0000FF"), "\"#FF0000FF\"");
    }

    #[test]
    fn hex_literal_no_hash() {
        assert_eq!(hex_literal("FF0000"), "\"#FF0000\"");
    }

    #[test]
    fn hex_literal_invalid() {
        assert_eq!(hex_literal("not-a-hex"), "\"not-a-hex\"");
    }
}
