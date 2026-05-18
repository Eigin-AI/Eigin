use super::parser::CatalogEntry;
use super::scope_tree;
use crate::codegen::ios;

const GENERATED_HEADER: &str =
    "import Foundation\n\n/// Auto-generated from Localizable.xcstrings. Do not edit manually.\n";

const TEMPLATE: &str = include_str!("templates/localized.swift.jinja");

pub fn emit(entries: &[CatalogEntry]) -> String {
    let mut env = minijinja::Environment::new();
    ios::install_filters(&mut env);
    env.add_template("localized", TEMPLATE)
        .expect("valid template");

    let tree = scope_tree::build_tree(entries);
    let body = tree.iter().map(|node| node.render(1)).collect::<String>();

    let ctx = minijinja::context!(header => GENERATED_HEADER, body => body);
    env.get_template("localized")
        .unwrap()
        .render(ctx)
        .expect("render succeeds")
}
