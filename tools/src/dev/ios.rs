use anyhow::{Context, Result, bail};
use std::fs;
use std::path::PathBuf;
use std::process::Command;

use super::device;
use super::logs::{self, Since};
use crate::config::model::Env;
use crate::config::render;
use crate::config::resolve;
use crate::exec;

/// The simulator every iOS recipe targets.
const SIMULATOR: &str = "iPhone 17 Pro";

/// Where the app writes its own log, inside its data container.
const APP_LOG: &str = "Documents/logs/eigin.log";

/// Build and launch on the simulator.
pub fn run_simulator(env: Env, root: &str) -> Result<()> {
    let app = App::for_env(env, root)?;
    // Fail before paying for code generation.
    let udid = simulator_udid()?;

    app.generate()?;
    exec::logged(
        &format!("Building {} for the simulator", app.scheme),
        &PathBuf::from(root).join("logs/ios-build.log"),
        Command::new("xcodebuild")
            .arg("-project")
            .arg(app.project())
            .args(["-scheme", &app.scheme])
            .args(["-destination", &format!("platform=iOS Simulator,id={udid}")])
            .args([
                "-derivedDataPath",
                &format!("{root}/src/eigin_ios/DerivedData"),
            ])
            .arg("-skipMacroValidation")
            .arg("build"),
    )?;

    let bundle_path = app.product("Debug-iphonesimulator")?;
    run_ok(Command::new("xcrun").args(["simctl", "bootstatus", &udid, "-b"]))?;
    run_ok(
        Command::new("xcrun")
            .args(["simctl", "install", &udid])
            .arg(&bundle_path),
    )?;
    run_ok(Command::new("xcrun").args([
        "simctl",
        "launch",
        "--terminate-running-process",
        &udid,
        &app.bundle_id,
    ]))?;

    println!(
        "→ {} running on {SIMULATOR}. logs: just logs ios simulator --follow",
        app.scheme
    );
    Ok(())
}

/// Build and launch on a paired iPhone, over the network.
pub fn run_device(name: Option<&str>, env: Env, root: &str) -> Result<()> {
    // Resolve the phone and the signing identity before generating anything.
    let device = device::resolve(name, true, root)?;
    let app = App::for_env(env, root)?;
    if app.team.is_empty() {
        bail!("DEVELOPMENT_TEAM is not set in .env — required to build for a physical device.");
    }

    app.generate()?;
    // xcodebuild destinations take the hardware UDID; devicectl takes the CoreDevice id.
    exec::logged(
        &format!("Building {} for {}", app.scheme, device.name),
        &PathBuf::from(root).join("logs/ios-build.log"),
        Command::new("xcodebuild")
            .arg("-project")
            .arg(app.project())
            .args(["-scheme", &app.scheme])
            .args(["-destination", &format!("platform=iOS,id={}", device.udid)])
            .args(["-configuration", "Debug"])
            .arg("-skipMacroValidation")
            .arg("-allowProvisioningUpdates")
            .arg("build"),
    )?;

    let bundle_path = app.product("Debug-iphoneos")?;
    run_ok(
        Command::new("xcrun")
            .args([
                "devicectl",
                "device",
                "install",
                "app",
                "--device",
                &device.id,
            ])
            .arg(&bundle_path),
    )?;
    run_ok(Command::new("xcrun").args([
        "devicectl",
        "device",
        "process",
        "launch",
        "--device",
        &device.id,
        "--terminate-existing",
        &app.bundle_id,
    ]))?;

    println!(
        "→ {} running on {}. logs: just logs ios device",
        app.scheme, device.name
    );
    Ok(())
}

/// Unified logging from the simulator, as a snapshot or a live stream.
pub fn simulator_logs(env: Env, since: &Since, follow: bool, root: &str) -> Result<()> {
    let app = App::for_env(env, root)?;
    let udid = simulator_udid()?;
    let predicate = format!("subsystem == \"{}\"", app.bundle_id);
    run_ok(Command::new("xcrun").args(["simctl", "bootstatus", &udid, "-b"]))?;

    let mut cmd = Command::new("xcrun");
    cmd.args(["simctl", "spawn", &udid, "log"]);
    if follow {
        eprintln!("Streaming {SIMULATOR} logs (ctrl-c to stop)…");
        cmd.args(["stream", "--level", "debug"]);
    } else {
        cmd.arg("show")
            .args(since.as_log_show_args())
            .args(["--info", "--debug"]);
    }
    cmd.args(["--style", "compact", "--predicate", &predicate]);
    run_ok(&mut cmd)
}

/// A snapshot of the app's own log, pulled off the phone.
///
/// `log collect` needs root for a paired device, so this reads the file the app
/// writes into its container instead — no privileges, and it works over the
/// network. There is no public way to stream it live.
pub fn device_logs(
    name: Option<&str>,
    env: Env,
    since: &Since,
    follow: bool,
    root: &str,
) -> Result<()> {
    if follow {
        bail!(
            "Physical devices support snapshots only, no live stream.\n\
             Use: just logs ios device [name] [env] [window] — or `just logs ios simulator --follow`"
        );
    }
    let device = device::resolve(name, false, root)?;
    let app = App::for_env(env, root)?;
    let destination = PathBuf::from(root).join("logs/ios-app.log");
    let _ = fs::remove_file(&destination);

    let pulled = Command::new("xcrun")
        .args([
            "devicectl",
            "device",
            "copy",
            "from",
            "--device",
            &device.id,
            "--domain-type",
            "appDataContainer",
            "--domain-identifier",
            &app.bundle_id,
            "--source",
            APP_LOG,
            "--destination",
        ])
        .arg(&destination)
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()
        .context("running devicectl device copy")?;
    if !pulled.success() {
        bail!(
            "Could not pull the app log from {}.\n\
             Check the phone is unlocked, awake and on the same network — and that it has\n\
             logged at least once (Settings → Advanced controls the file log).",
            device.name
        );
    }

    let text = fs::read_to_string(&destination).context("reading the pulled app log")?;
    print!(
        "{}",
        logs::filter_since(&text, &since.cutoff(logs::now_unix()))
    );
    Ok(())
}

/// The scheme, bundle id and signing team for one environment.
///
/// All three come from the same place `project.yml` reads them from, so the app
/// this launches is the app that was generated.
struct App {
    scheme: String,
    bundle_id: String,
    team: String,
    root: String,
    env_vars: Vec<(String, String)>,
}

impl App {
    fn for_env(env: Env, root: &str) -> Result<App> {
        let resolved = resolve::resolve(root)?;
        let rendered = render::ios::render(&resolved);
        let vars = render::shell::parse_exports(&rendered.exports);
        let value = |key: &str| {
            vars.iter()
                .find(|(k, _)| k == key)
                .map(|(_, v)| v.clone())
                .unwrap_or_default()
        };
        let bundle_id = match env {
            Env::Staging => format!("{}.dev", value("BUNDLE_ID")),
            Env::Production => value("BUNDLE_ID"),
        };
        Ok(App {
            scheme: match env {
                Env::Staging => "EiginDev".into(),
                Env::Production => "Eigin".into(),
            },
            bundle_id,
            team: value("DEVELOPMENT_TEAM"),
            root: root.to_string(),
            env_vars: vars,
        })
    }

    fn project(&self) -> PathBuf {
        PathBuf::from(&self.root).join("src/eigin_ios/Eigin-iOS.xcodeproj")
    }

    /// XcodeGen's presets place products under `$SRCROOT/Build`, whatever
    /// `-derivedDataPath` says.
    fn product(&self, configuration: &str) -> Result<PathBuf> {
        let path = PathBuf::from(&self.root)
            .join("src/eigin_ios/Build/Products")
            .join(configuration)
            .join(format!("{}.app", self.scheme));
        if !path.is_dir() {
            bail!("build product not found: {}", path.display());
        }
        Ok(path)
    }

    /// Regenerate the project, with the same environment xcodegen expects.
    fn generate(&self) -> Result<()> {
        for (key, value) in &self.env_vars {
            // Safe here: this is a single-threaded CLI, before anything is spawned.
            unsafe { std::env::set_var(key, value) };
        }
        crate::generate::run(crate::generate::GenerateArgs::default())
    }
}

fn simulator_udid() -> Result<String> {
    let out = Command::new("xcrun")
        .args(["simctl", "list", "devices", "--json"])
        .output()
        .context("running xcrun simctl list devices")?;
    let listing: serde_json::Value =
        serde_json::from_slice(&out.stdout).context("parsing simctl output")?;

    let runtimes = listing["devices"]
        .as_object()
        .context("no simulators listed")?;
    let mut found = None;
    for (_, devices) in runtimes {
        for device in devices.as_array().into_iter().flatten() {
            if device["name"] == SIMULATOR {
                let udid = device["udid"].as_str().unwrap_or_default().to_string();
                // Prefer one that's already booted, to match what the user is looking at.
                if device["state"] == "Booted" {
                    return Ok(udid);
                }
                found.get_or_insert(udid);
            }
        }
    }
    found.with_context(|| {
        format!("No '{SIMULATOR}' simulator. Create it in Xcode, or change SIMULATOR in tools.")
    })
}

fn run_ok(cmd: &mut Command) -> Result<()> {
    let status = cmd
        .status()
        .with_context(|| format!("running {:?}", cmd.get_program()))?;
    if !status.success() {
        bail!("{:?} failed", cmd.get_program());
    }
    Ok(())
}
