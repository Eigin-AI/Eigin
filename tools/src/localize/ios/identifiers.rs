pub fn pascal_cased(s: &str) -> String {
    s.split('-')
        .filter(|p| !p.is_empty())
        .map(|part| {
            let mut chars = part.chars();
            match chars.next() {
                None => String::new(),
                Some(c) => c.to_uppercase().collect::<String>() + chars.as_str(),
            }
        })
        .collect()
}

pub fn camel_cased(s: &str) -> String {
    let parts: Vec<&str> = s.split('-').filter(|p| !p.is_empty()).collect();
    if parts.is_empty() {
        return s.to_string();
    }
    let rest: String = parts[1..]
        .iter()
        .map(|p| {
            let mut chars = p.chars();
            match chars.next() {
                None => String::new(),
                Some(c) => c.to_uppercase().collect::<String>() + chars.as_str(),
            }
        })
        .collect();
    parts[0].to_string() + &rest
}

/// Strips characters that are not valid in a Swift identifier.
pub fn sanitize_identifier(s: &str) -> String {
    s.chars()
        .filter(|c| c.is_alphanumeric() || *c == '_')
        .collect()
}

/// Renames pascal-cased enum container names that conflict with Swift built-ins.
/// `Type` conflicts with the `foo.Type` metatype expression.
pub fn safe_enum_name(name: String) -> String {
    match name.as_str() {
        "Type" => "Kind".to_string(),
        _ => name,
    }
}

/// Wraps Swift keywords in backticks so they can be used as member names.
pub fn escape_if_needed(ident: &str) -> String {
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

pub fn is_valid_swift_identifier(s: &str) -> bool {
    let mut chars = s.chars();
    match chars.next() {
        None => false,
        Some(c) if !c.is_alphabetic() && c != '_' => false,
        _ => chars.all(|c| c.is_alphanumeric() || c == '_' || c == '-'),
    }
}
