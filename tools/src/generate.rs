use anyhow::{Context, Result};
use std::process::Command;

use crate::codegen;
use crate::config;
use crate::design;
use crate::knowledge;
use crate::localize;
use crate::prompts;

/// Generate host SDK artifacts and application outputs.
///
/// iOS generation needs Apple SDK tooling; web and SDK web targets stay portable.
/// XcodeGen and build-server configuration follow source and binding generation.
#[derive(clap::Args, Default)]
pub struct GenerateArgs {
    /// Generation target: all (default), ios, web, docs, or sdk.
    #[arg(value_enum, default_value_t = GenerateTarget::All)]
    target: GenerateTarget,
    /// SDK host artifacts (only valid after sdk).
    #[arg(value_enum)]
    sdk_target: Option<crate::sdk::SdkTarget>,
}

impl GenerateArgs {
    /// Select only the outputs required by the iOS application.
    pub fn ios() -> Self {
        Self {
            target: GenerateTarget::Ios,
            sdk_target: None,
        }
    }
}

/// Independently selectable generation outputs.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, clap::ValueEnum)]
enum GenerateTarget {
    #[default]
    All,
    Ios,
    Web,
    Sdk,
    Docs,
}

pub fn run(args: GenerateArgs) -> Result<()> {
    let root = config::repo_root()?;
    if args.target == GenerateTarget::Sdk {
        return crate::sdk::generate(&root, args.sdk_target.unwrap_or_default());
    }
    if args.sdk_target.is_some() {
        anyhow::bail!("SDK host selector requires `generate sdk [apple | web | all]`");
    }
    if args.target == GenerateTarget::Docs {
        return design::web::generate_docs(&root);
    }
    if args.target == GenerateTarget::Web {
        design::web::generate_assets(&root)?;
        return crate::sdk::generate(&root, crate::sdk::SdkTarget::Web);
    }
    crate::sdk::generate(&root, crate::sdk::SdkTarget::Apple)?;
    if args.target == GenerateTarget::All {
        crate::sdk::generate(&root, crate::sdk::SdkTarget::Web)?;
    }
    let ios_dir = format!("{root}/src/eigin_ios");

    // Run all codegen before xcodegen so generated files are on disk
    // when xcodegen scans the source directories.
    localize::generate_all(&root)?;
    match args.target {
        GenerateTarget::All => design::generate_all(&root)?,
        GenerateTarget::Ios => design::generate_ios(&root)?,
        GenerateTarget::Web | GenerateTarget::Sdk | GenerateTarget::Docs => {
            unreachable!("target returned above")
        }
    }
    prompts::generate_all(&root)?;
    knowledge::generate_all(&root)?;

    // The prompt and knowledge registries used to be generated into the design
    // folder. They are gitignored, so a checkout predating the move keeps the
    // old copies and the widget extension — which compiles Design/Generated —
    // fails on the duplicate filenames.
    codegen::remove_stale_duplicates(
        &format!("{ios_dir}/Sources/Core/Content/Generated"),
        &format!("{ios_dir}/Sources/Core/Design/Generated"),
    )?;

    if !is_installed("xcodegen") {
        println!("Skipping the Xcode project: xcodegen not installed (needed for iOS work).");
        return Ok(());
    }

    run_cmd(
        Command::new("xcodegen")
            .arg("generate")
            .env("BUNDLE_ID", bundle_id(&root)?)
            .current_dir(&ios_dir),
        "xcodegen generate",
    )?;

    // IDE/LSP convenience only, and the one step that genuinely needs Xcode.
    if !is_installed("xcodebuild") || !is_installed("xcode-build-server") {
        println!("Skipping the build server config: needs Xcode and xcode-build-server.");
        return Ok(());
    }

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

/// Bundle identifier for the generated project, from `config/app.toml`.
fn bundle_id(root: &str) -> Result<String> {
    Ok(config::load(root)?.app.identity.bundle_id)
}

/// Whether a command can be run, used to skip steps whose tool is absent.
fn is_installed(name: &str) -> bool {
    Command::new(name)
        .arg("--version")
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .is_ok()
}

fn run_cmd(cmd: &mut Command, label: &str) -> Result<()> {
    let status = cmd.status().with_context(|| format!("running {label}"))?;
    if !status.success() {
        anyhow::bail!("{label} failed");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::Parser;

    #[derive(Parser)]
    struct Cli {
        #[command(flatten)]
        args: GenerateArgs,
    }

    #[test]
    fn generation_targets_are_explicit() {
        for (args, expected) in [
            (vec!["generate"], GenerateTarget::All),
            (vec!["generate", "all"], GenerateTarget::All),
            (vec!["generate", "ios"], GenerateTarget::Ios),
            (vec!["generate", "web"], GenerateTarget::Web),
            (vec!["generate", "docs"], GenerateTarget::Docs),
            (vec!["generate", "sdk"], GenerateTarget::Sdk),
        ] {
            assert_eq!(Cli::try_parse_from(args).unwrap().args.target, expected);
        }
        for selector in ["apple", "web", "all"] {
            let parsed = Cli::try_parse_from(["generate", "sdk", selector]).unwrap();
            assert_eq!(parsed.args.target, GenerateTarget::Sdk);
            assert!(parsed.args.sdk_target.is_some());
        }
        assert!(Cli::try_parse_from(["generate", "sdk", "invalid"]).is_err());
        assert!(Cli::try_parse_from(["generate", "relay"]).is_err());
        assert!(Cli::try_parse_from(["generate", "--web"]).is_err());
    }
}
