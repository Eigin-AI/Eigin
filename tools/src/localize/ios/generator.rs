use super::identifiers::{
    camel_cased, escape_if_needed, pascal_cased, safe_enum_name, sanitize_identifier,
};
use super::parser::CatalogEntry;

pub fn emit(entries: &[CatalogEntry]) -> String {
    let mut output = concat!(
        "import Foundation\n",
        "\n",
        "/// Auto-generated from Localizable.xcstrings. Do not edit manually.\n",
        "enum Localized {\n",
        "    /// Always returns the bundle for the currently selected language.\n",
        "    /// Computed each time so language changes are reflected immediately.\n",
        "    static var bundle: Bundle { .appLanguage }\n",
        "\n",
        "    private static func get(_ key: String) -> String {\n",
        "        bundle.localizedString(forKey: key, value: nil, table: nil)\n",
        "    }\n",
        "\n",
    )
    .to_string();

    let mut scope_stack: Vec<String> = Vec::new();

    for entry in entries {
        let segments: Vec<&str> = entry.key.split('.').collect();
        let container_path = &segments[..segments.len() - 1];
        let leaf_segment = segments.last().unwrap();

        // Find how many leading segments match the current scope
        let common_len = scope_stack
            .iter()
            .zip(container_path.iter())
            .take_while(|(a, b)| a.as_str() == **b)
            .count();

        // Close scopes that no longer match
        while scope_stack.len() > common_len {
            let depth = scope_stack.len() - 1;
            output.push_str(&format!("{}}}\n", indent(depth)));
            scope_stack.pop();
        }

        // Open new scopes for diverging segments
        for i in common_len..container_path.len() {
            let seg = container_path[i];
            let depth = i;
            let pascal_seg = safe_enum_name(pascal_cased(seg));
            output.push_str(&format!("{}enum {} {{\n", indent(depth), pascal_seg));
            scope_stack.push(seg.to_string());
        }

        // Write the leaf member
        let leaf_depth = container_path.len();
        let leaf_indent = indent(leaf_depth);
        let swift_name = escape_if_needed(&sanitize_identifier(&camel_cased(leaf_segment)));

        if let Some(comment) = &entry.comment {
            output.push_str(&format!("{}/// {}\n", leaf_indent, comment));
        }

        if entry.param_count > 0 {
            let params: String = (1..=entry.param_count)
                .map(|i| format!("_ p{i}: String"))
                .collect::<Vec<_>>()
                .join(", ");
            let param_names: String = (1..=entry.param_count)
                .map(|i| format!("p{i}"))
                .collect::<Vec<_>>()
                .join(", ");
            output.push_str(&format!(
                "{}static func {}({}) -> String {{\n",
                leaf_indent, swift_name, params
            ));
            output.push_str(&format!(
                "{}    String(format: Localized.get(\"{}\"), {})\n",
                leaf_indent, entry.key, param_names
            ));
            output.push_str(&format!("{}}}\n", leaf_indent));
        } else {
            output.push_str(&format!(
                "{}static var {}: String {{ Localized.get(\"{}\") }}\n",
                leaf_indent, swift_name, entry.key
            ));
        }
    }

    // Close all remaining open scopes
    while !scope_stack.is_empty() {
        let depth = scope_stack.len() - 1;
        output.push_str(&format!("{}}}\n", indent(depth)));
        scope_stack.pop();
    }

    output.push_str("}\n");
    output
}

fn indent(depth: usize) -> String {
    "    ".repeat(depth + 1)
}
