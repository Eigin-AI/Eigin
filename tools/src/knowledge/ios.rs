use anyhow::{Context, Result, bail};
use firm_lang::diagnostics::{self, Diagnostic, DiagnosticSeverity};
use firm_lang::workspace::Workspace;
use std::collections::BTreeSet;
use std::fmt::Write as _;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const WORKSPACE_REL: &str = "design/knowledge";
const OUTPUT_REL: &str =
    "src/eigin_ios/Sources/Core/Design/Generated/BundledKnowledgeRegistry.swift";

/// The name of the ontology source at the workspace root. Every other `.firm`
/// file lives in a `<type>/` subfolder and maps to exactly one entity.
const SCHEMAS_FILE: &str = "schemas.firm";

/// One seed-entity source: its type, short id, and verbatim `.firm` content.
struct SeedEntity {
    type_name: String,
    id: String,
    content: String,
}

/// The parsed `design/knowledge` workspace: the ontology plus every seed entity.
struct Knowledge {
    schemas: String,
    entities: Vec<SeedEntity>,
}

/// Compile `design/knowledge/**/*.firm` into
/// `Sources/Core/Design/Generated/BundledKnowledgeRegistry.swift`, validating the
/// workspace through the firm language crate first so a malformed or dangling
/// source fails generation instead of shipping. Called by `eigin-tools generate`.
pub fn generate(repo_root: &str) -> Result<()> {
    let workspace_dir = PathBuf::from(repo_root).join(WORKSPACE_REL);
    let output_path = PathBuf::from(repo_root).join(OUTPUT_REL);

    if !workspace_dir.exists() {
        if output_path.exists() {
            fs::remove_file(&output_path)
                .with_context(|| format!("removing {}", output_path.display()))?;
        }
        return Ok(());
    }

    let knowledge = collect(&workspace_dir)?;
    validate(&workspace_dir)?;
    let swift = emit(&knowledge);
    write_swift(&output_path, &swift)?;
    Ok(())
}

/// Read the workspace into memory: `schemas.firm` at the root, and one
/// `SeedEntity` per `<type>/<id>.firm`. Content is trimmed of trailing
/// whitespace so it matches an equivalent Swift `"""` literal byte-for-byte.
/// Entities are sorted by `(type, id)` for stable output.
fn collect(workspace_dir: &Path) -> Result<Knowledge> {
    let schemas_path = workspace_dir.join(SCHEMAS_FILE);
    let schemas = read_trimmed(&schemas_path)?;
    if schemas.is_empty() {
        bail!("{} is empty", schemas_path.display());
    }

    let mut entities = Vec::new();
    let mut seen = BTreeSet::new();
    for type_entry in fs::read_dir(workspace_dir)
        .with_context(|| format!("reading {}", workspace_dir.display()))?
    {
        let type_path = type_entry?.path();
        if !type_path.is_dir() {
            continue;
        }
        let type_name = file_name(&type_path)?;
        for entry in
            fs::read_dir(&type_path).with_context(|| format!("reading {}", type_path.display()))?
        {
            let path = entry?.path();
            if path.extension().and_then(|s| s.to_str()) != Some("firm") {
                continue;
            }
            let id = path
                .file_stem()
                .and_then(|s| s.to_str())
                .ok_or_else(|| anyhow::anyhow!("non-utf8 file {}", path.display()))?
                .to_string();
            if !seen.insert((type_name.clone(), id.clone())) {
                bail!("duplicate entity {type_name}/{id}");
            }
            entities.push(SeedEntity {
                type_name: type_name.clone(),
                id,
                content: read_trimmed(&path)?,
            });
        }
    }

    entities.sort_by(|a, b| (&a.type_name, &a.id).cmp(&(&b.type_name, &b.id)));
    Ok(Knowledge { schemas, entities })
}

/// Load the workspace through the firm language crate — the same engine the app
/// runs — and fail on any error-severity diagnostic or build failure. A source
/// that validates here will load at runtime.
fn validate(workspace_dir: &Path) -> Result<()> {
    let mut workspace = Workspace::new();
    workspace
        .load_directory(&workspace_dir.to_path_buf())
        .map_err(|e| {
            anyhow::anyhow!("loading firm workspace {}: {e:?}", workspace_dir.display())
        })?;

    let mut errors: Vec<String> = workspace
        .parsed_sources()
        .into_iter()
        .flat_map(diagnostics::collect_syntax_errors)
        .filter(is_error)
        .map(format_diagnostic)
        .collect();

    // Cross-file checks (reference integrity, schema consistency) only run once
    // every source parses, mirroring the firm tooling's own ordering.
    if errors.is_empty() {
        errors = diagnostics::collect_workspace_diagnostics(&workspace)
            .into_iter()
            .filter(is_error)
            .map(format_diagnostic)
            .collect();
    }

    if !errors.is_empty() {
        bail!(
            "firm validation failed for {}:\n{}",
            workspace_dir.display(),
            errors.join("\n")
        );
    }

    workspace
        .build()
        .map_err(|e| anyhow::anyhow!("building firm workspace: {e:?}"))?;
    Ok(())
}

fn is_error(diagnostic: &Diagnostic) -> bool {
    matches!(diagnostic.severity, DiagnosticSeverity::Error)
}

fn format_diagnostic(diagnostic: Diagnostic) -> String {
    format!(
        "  {}:{}:{}: {}",
        diagnostic.span.file.display(),
        diagnostic.span.start_line,
        diagnostic.span.start_col,
        diagnostic.message
    )
}

/// Emit `BundledKnowledgeRegistry.swift`: the schemas constant plus a
/// `(type, id, content)` manifest of every seed entity. Firm content is written
/// as escaped single-line Swift string literals, so swiftformat leaves it alone.
fn emit(knowledge: &Knowledge) -> String {
    let mut out = String::from(
        "// Generated by eigin-tools — edit design/knowledge/**/*.firm, not this file.\n",
    );
    out.push_str("import Foundation\n\n");
    out.push_str("/// Bundled knowledge compiled from the design/knowledge firm workspace.\n");
    out.push_str("/// Edit the `.firm` sources, not this file.\n");
    out.push_str("enum BundledKnowledgeRegistry {\n");
    writeln!(
        out,
        "    static let schemas = \"{}\"\n",
        escape(&knowledge.schemas)
    )
    .unwrap();
    out.push_str(
        "    static let seedEntities: [(type: String, id: String, content: String)] = [\n",
    );
    for entity in &knowledge.entities {
        writeln!(
            out,
            "        (type: \"{}\", id: \"{}\", content: \"{}\"),",
            escape(&entity.type_name),
            escape(&entity.id),
            escape(&entity.content)
        )
        .unwrap();
    }
    out.push_str("    ]\n");
    out.push_str("}\n");
    out
}

fn read_trimmed(path: &Path) -> Result<String> {
    Ok(fs::read_to_string(path)
        .with_context(|| format!("reading {}", path.display()))?
        .trim_end()
        .to_string())
}

fn file_name(path: &Path) -> Result<String> {
    Ok(path
        .file_name()
        .and_then(|s| s.to_str())
        .ok_or_else(|| anyhow::anyhow!("non-utf8 path {}", path.display()))?
        .to_string())
}

/// Escape a string for embedding inside a single-line Swift `"..."` literal.
fn escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '\\' => out.push_str("\\\\"),
            '"' => out.push_str("\\\""),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            '\0' => out.push_str("\\0"),
            _ => out.push(c),
        }
    }
    out
}

fn write_swift(output_path: &Path, swift: &str) -> Result<()> {
    let parent = output_path.parent().unwrap();
    fs::create_dir_all(parent).with_context(|| format!("creating {}", parent.display()))?;
    fs::write(output_path, swift).with_context(|| format!("writing {}", output_path.display()))?;

    let status = Command::new("swiftformat")
        .arg(output_path)
        .status()
        .context("running swiftformat")?;
    if !status.success() {
        bail!("swiftformat failed on {}", output_path.display());
    }

    println!("Generated {}", output_path.display());
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::TempDir;

    fn workspace(files: &[(&str, &str)]) -> TempDir {
        let dir = TempDir::new().unwrap();
        for (rel, content) in files {
            let path = dir.path().join(rel);
            fs::create_dir_all(path.parent().unwrap()).unwrap();
            fs::write(path, content).unwrap();
        }
        dir
    }

    #[test]
    fn collects_type_and_id_from_path() {
        let dir = workspace(&[
            ("schemas.firm", "schema fact { }\n"),
            ("fact/a.firm", "fact a { claim = \"x\" }\n"),
            ("thing/eigin.firm", "thing eigin { name = \"Eigin\" }\n"),
        ]);
        let knowledge = collect(dir.path()).unwrap();
        assert_eq!(knowledge.schemas, "schema fact { }");
        // Sorted by (type, id): fact/a before thing/eigin.
        assert_eq!(knowledge.entities.len(), 2);
        assert_eq!(knowledge.entities[0].type_name, "fact");
        assert_eq!(knowledge.entities[0].id, "a");
        assert_eq!(knowledge.entities[1].type_name, "thing");
        assert_eq!(knowledge.entities[1].id, "eigin");
    }

    #[test]
    fn trims_trailing_whitespace() {
        let dir = workspace(&[
            ("schemas.firm", "schema fact { }\n\n"),
            ("fact/a.firm", "fact a { }\n"),
        ]);
        let knowledge = collect(dir.path()).unwrap();
        assert_eq!(knowledge.schemas, "schema fact { }");
        assert_eq!(knowledge.entities[0].content, "fact a { }");
    }

    #[test]
    fn ignores_non_firm_files() {
        let dir = workspace(&[
            ("schemas.firm", "schema fact { }\n"),
            ("fact/a.firm", "fact a { }\n"),
            ("fact/README.md", "not an entity\n"),
        ]);
        let knowledge = collect(dir.path()).unwrap();
        assert_eq!(knowledge.entities.len(), 1);
    }

    #[test]
    fn emits_schemas_and_manifest() {
        let knowledge = Knowledge {
            schemas: "schema fact { }".into(),
            entities: vec![SeedEntity {
                type_name: "fact".into(),
                id: "a".into(),
                content: "fact a {\n    claim = \"x\"\n}".into(),
            }],
        };
        let swift = emit(&knowledge);
        assert!(swift.contains("enum BundledKnowledgeRegistry {"));
        assert!(swift.contains("static let schemas = \"schema fact { }\""));
        assert!(swift.contains(
            "static let seedEntities: [(type: String, id: String, content: String)] = ["
        ));
        assert!(swift.contains(
            "(type: \"fact\", id: \"a\", content: \"fact a {\\n    claim = \\\"x\\\"\\n}\"),"
        ));
    }

    #[test]
    fn escapes_quotes_and_newlines() {
        assert_eq!(escape("a\"b\nc"), "a\\\"b\\nc");
    }
}
