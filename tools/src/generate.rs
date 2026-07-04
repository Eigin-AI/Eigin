use anyhow::{Context, Result};
use std::path::PathBuf;
use std::process::Command;

use crate::config;
use crate::design;
use crate::knowledge;
use crate::localize;
use crate::prompts;

/// Run all code generation tasks for the project.
///
/// - iOS: generates the Xcode project from project.yml via xcodegen,
///   then updates the build server config for IDE/LSP support.
/// - All platforms: generates localization source files from catalog.
#[derive(clap::Args)]
pub struct GenerateArgs {}

pub fn run(_args: GenerateArgs) -> Result<()> {
    let root = config::repo_root()?;
    let ios_dir = format!("{root}/src/eigin_ios");

    // Run all codegen before xcodegen so generated files are on disk
    // when xcodegen scans the source directories.
    localize::generate_all(&root)?;
    design::generate_all(&root)?;
    prompts::generate_all(&root)?;
    knowledge::generate_all(&root)?;

    run_cmd(
        Command::new("xcodegen")
            .arg("generate")
            .current_dir(&ios_dir),
        "xcodegen generate",
    )?;

    // LiteRT-LM ships Android/Windows prebuilt binaries via Git LFS. Those
    // objects are not present in the LFS store for all revisions, so `git
    // checkout` fails when `filter.lfs.required=true` (the git-lfs default).
    // We don't need those files — Package.swift fetches an XCFramework from
    // GitHub Releases instead. Disable the LFS smudge requirement in every
    // LiteRT-LM checkout SPM has resolved so git treats the LFS pointers as
    // plain text stubs rather than aborting the checkout.
    patch_litert_lfs_required();
    patch_litert_conversation_close();

    run_cmd(
        Command::new("xcode-build-server")
            .args([
                "config",
                "-project",
                "Eigin-iOS.xcodeproj",
                "-scheme",
                "Eigin",
            ])
            .current_dir(&ios_dir),
        "xcode-build-server config",
    )?;

    Ok(())
}

/// Find every SPM checkout of LiteRT-LM under `~/Library/Developer/Xcode/DerivedData`
/// and set `filter.lfs.required=false` in its local git config so that missing
/// LFS objects (Android/Windows prebuilts) don't abort the checkout.
fn patch_litert_lfs_required() {
    let Some(home) = dirs::home_dir() else { return };
    let derived_data = home.join("Library/Developer/Xcode/DerivedData");

    // Walk: DerivedData/<project-hash>/SourcePackages/checkouts/LiteRT-LM
    let checkouts_glob = derived_data.join("*/SourcePackages/checkouts/LiteRT-LM");
    let pattern = checkouts_glob.to_string_lossy();

    let paths: Vec<PathBuf> = glob::glob(&pattern)
        .into_iter()
        .flatten()
        .flatten()
        .collect();

    for checkout in paths {
        let result = Command::new("git")
            .args(["config", "filter.lfs.required", "false"])
            .current_dir(&checkout)
            .status();
        match result {
            Ok(s) if s.success() => {}
            _ => {
                // Non-fatal: the build may still succeed if the LFS objects
                // happen to be available, or if the checkout is already complete.
                eprintln!(
                    "warning: could not patch LFS config in {}",
                    checkout.display()
                );
            }
        }
    }
}

/// Patch `Conversation.swift` in every LiteRT-LM checkout to add an explicit
/// `close()` method. LiteRT-LM allows only one active session per engine;
/// Swift's ARC does not guarantee synchronous deallocation across async
/// suspension points, so we cannot rely on `deinit` to free the session slot.
/// `close()` calls `litert_lm_conversation_delete` synchronously so callers
/// can free the session before the next `createConversation` call.
fn patch_litert_conversation_close() {
    let Some(home) = dirs::home_dir() else { return };
    let derived_data = home.join("Library/Developer/Xcode/DerivedData");
    let pattern = derived_data
        .join("*/SourcePackages/checkouts/LiteRT-LM/swift/Conversation.swift")
        .to_string_lossy()
        .into_owned();

    let paths: Vec<PathBuf> = glob::glob(&pattern)
        .into_iter()
        .flatten()
        .flatten()
        .collect();

    let marker = "public func close()";
    let injection = r#"
  /// Explicitly deletes the native conversation and releases the engine session slot.
  ///
  /// Call this before creating a new ``Conversation`` from the same ``Engine``.
  /// LiteRT-LM allows only one active session per engine; failing to close the
  /// previous conversation before creating a new one results in a
  /// `FAILED_PRECONDITION: A session already exists` error.
  ///
  /// After calling `close()`, the conversation is no longer usable (`isAlive` returns `false`).
  public func close() {
    guard let h = handle else { return }
    litert_lm_conversation_delete(h)
    handle = nil
  }
"#;
    let anchor = "  /// Cancels the ongoing asynchronous inference process.";

    for path in paths {
        let Ok(content) = std::fs::read_to_string(&path) else {
            continue;
        };
        if content.contains(marker) {
            continue; // already patched
        }
        let patched = content.replacen(anchor, &format!("{injection}{anchor}"), 1);
        if patched == content {
            eprintln!(
                "warning: could not find anchor to inject close() in {}",
                path.display()
            );
            continue;
        }
        if let Err(e) = std::fs::write(&path, &patched) {
            eprintln!(
                "warning: could not patch Conversation.swift at {}: {e}",
                path.display()
            );
        }
    }
}

fn run_cmd(cmd: &mut Command, label: &str) -> Result<()> {
    let status = cmd.status().with_context(|| format!("running {label}"))?;
    if !status.success() {
        anyhow::bail!("{label} failed");
    }
    Ok(())
}
