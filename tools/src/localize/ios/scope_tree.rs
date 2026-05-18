use super::identifiers::{escape_if_needed, pascal_cased, safe_enum_name, sanitize_identifier};
use super::parser::CatalogEntry;

pub fn build_tree(entries: &[CatalogEntry]) -> Vec<ScopeNode> {
    let mut root = ScopeNode::new("");
    for entry in entries {
        let segments: Vec<&str> = entry.key.split('.').collect();
        let container = &segments[..segments.len() - 1];
        let leaf = segments.last().unwrap();
        root.insert(container, leaf, entry);
    }
    root.children
}

#[derive(Clone, Debug, serde::Serialize)]
pub struct ScopeNode {
    pub name: String,
    pub children: Vec<ScopeNode>,
    pub leaves: Vec<ScopeLeaf>,
}

#[derive(Clone, Debug, serde::Serialize)]
pub struct ScopeLeaf {
    pub key: String,
    pub swift_name: String,
    pub param_count: usize,
    pub comment: Option<String>,
}

impl ScopeNode {
    pub fn new(name: &str) -> Self {
        Self {
            name: name.to_string(),
            children: Vec::new(),
            leaves: Vec::new(),
        }
    }

    fn insert(&mut self, path: &[&str], leaf: &str, entry: &CatalogEntry) {
        if path.is_empty() {
            let swift_name =
                escape_if_needed(&sanitize_identifier(&super::identifiers::camel_cased(leaf)))
                    .to_string();
            self.leaves.push(ScopeLeaf {
                key: entry.key.clone(),
                swift_name,
                param_count: entry.param_count,
                comment: entry.comment.clone(),
            });
        } else {
            let head = path[0];
            let tail = &path[1..];
            let name = safe_enum_name(pascal_cased(head));
            let idx = self.children.iter().position(|c| c.name == name);
            let child = match idx {
                Some(i) => &mut self.children[i],
                None => {
                    let node = Self::new(&name);
                    self.children.push(node);
                    self.children.last_mut().unwrap()
                }
            };
            child.insert(tail, leaf, entry);
        }
    }

    /// Renders this node and its descendants as Swift `enum` / `static`
    /// declarations.
    ///
    /// This stays in Rust rather than moving into a `localized.swift.jinja`
    /// template because minijinja has no macro recursion. Recursive loops
    /// (`for item recursive`) are supported, but indent-level arithmetic and
    /// trailing-comma placement are simpler and more testable in code.
    pub fn render(&self, depth: usize) -> String {
        let indent = "    ".repeat(depth);
        let mut out = String::new();

        let is_root = self.name.is_empty();
        let inner_depth = if is_root { depth } else { depth + 1 };

        if !is_root {
            out.push_str(&format!("{indent}enum {} {{\n", self.name));
        }

        let inner_indent = "    ".repeat(inner_depth);
        for leaf in &self.leaves {
            if let Some(ref comment) = leaf.comment {
                out.push_str(&format!("{inner_indent}/// {}\n", comment));
            }
            if leaf.param_count > 0 {
                let params: Vec<String> = (1..=leaf.param_count)
                    .map(|i| format!("_ p{i}: String"))
                    .collect();
                let param_names: Vec<String> =
                    (1..=leaf.param_count).map(|i| format!("p{i}")).collect();
                out.push_str(&format!(
                    "{inner_indent}static func {}({}) -> String {{\n",
                    leaf.swift_name,
                    params.join(", ")
                ));
                out.push_str(&format!(
                    "{inner_indent}    String(format: Localized.get(\"{}\"), {})\n",
                    leaf.key,
                    param_names.join(", ")
                ));
                out.push_str(&format!("{inner_indent}}}\n"));
            } else {
                out.push_str(&format!(
                    "{inner_indent}static var {}: String {{ Localized.get(\"{}\") }}\n",
                    leaf.swift_name, leaf.key
                ));
            }
        }

        for child in &self.children {
            out.push_str(&child.render(inner_depth));
        }

        if !is_root {
            out.push_str(&format!("{indent}}}\n"));
        }

        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(key: &str, comment: Option<&str>, params: usize) -> CatalogEntry {
        CatalogEntry {
            key: key.to_string(),
            comment: comment.map(String::from),
            param_count: params,
        }
    }

    #[test]
    fn build_flat_leaves() {
        let entries = vec![
            entry("chat.title", Some("The chat title"), 0),
            entry("chat.body", None, 0),
        ];
        let tree = build_tree(&entries);
        assert_eq!(tree.len(), 1);
        assert_eq!(tree[0].name, "Chat");
        assert_eq!(tree[0].leaves.len(), 2);
        assert_eq!(tree[0].children.len(), 0);
    }

    #[test]
    fn build_nested_scopes() {
        let entries = vec![
            entry("ui.button.primary", None, 0),
            entry("ui.button.secondary", None, 0),
            entry("ui.label.header", None, 0),
        ];
        let tree = build_tree(&entries);
        assert_eq!(tree.len(), 1);
        let ui = &tree[0];
        assert_eq!(ui.name, "Ui");
        assert_eq!(ui.children.len(), 2);
        assert_eq!(ui.leaves.len(), 0);

        let button = &ui.children[0];
        assert_eq!(button.name, "Button");
        assert_eq!(button.leaves.len(), 2);

        let label = &ui.children[1];
        assert_eq!(label.name, "Label");
        assert_eq!(label.leaves.len(), 1);
    }

    #[test]
    fn render_static_var() {
        let node = ScopeNode {
            name: "Chat".to_string(),
            children: vec![],
            leaves: vec![ScopeLeaf {
                key: "chat.title".to_string(),
                swift_name: "title".to_string(),
                param_count: 0,
                comment: None,
            }],
        };
        let out = node.render(1);
        assert!(out.contains("enum Chat {"));
        assert!(out.contains("static var title: String { Localized.get(\"chat.title\") }"));
    }

    #[test]
    fn render_func_with_params() {
        let node = ScopeNode {
            name: "Agent".to_string(),
            children: vec![],
            leaves: vec![ScopeLeaf {
                key: "agent.greeting".to_string(),
                swift_name: "greeting".to_string(),
                param_count: 1,
                comment: None,
            }],
        };
        let out = node.render(1);
        assert!(out.contains("static func greeting(_ p1: String) -> String {"));
        assert!(out.contains("String(format: Localized.get(\"agent.greeting\"), p1)"));
    }

    #[test]
    fn render_doc_comment() {
        let node = ScopeNode {
            name: "Chat".to_string(),
            children: vec![],
            leaves: vec![ScopeLeaf {
                key: "chat.title".to_string(),
                swift_name: "title".to_string(),
                param_count: 0,
                comment: Some("The chat title".to_string()),
            }],
        };
        let out = node.render(1);
        assert!(out.contains("/// The chat title"));
    }

    #[test]
    fn render_root_flat() {
        let root = ScopeNode::new("");
        let tree = vec![root];
        let out = tree[0].render(1);
        assert!(!out.contains("enum "));
    }
}
