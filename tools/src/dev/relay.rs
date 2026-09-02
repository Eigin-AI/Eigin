use anyhow::{Context, Result, bail};
use std::fs;
use std::net::{SocketAddr, TcpStream};
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::Command;
use std::time::Duration;

use super::logs::{self, Since};
use crate::config::model::Env;
use crate::config::render;
use crate::config::resolve;

const DEFAULT_PORT: u16 = 8080;
const READY_TIMEOUT: Duration = Duration::from_secs(30);

fn log_file(root: &str) -> PathBuf {
    PathBuf::from(root).join("logs/relay.log")
}

fn pid_file(root: &str) -> PathBuf {
    PathBuf::from(root).join("logs/relay.pid")
}

/// Build and start the relay, detached, replacing an instance we started before.
pub fn start(env: Env, root: &str) -> Result<()> {
    let relay_dir = PathBuf::from(root).join("src/eigin_relay");
    fs::create_dir_all(PathBuf::from(root).join("logs")).context("creating the logs directory")?;

    let resolved = resolve::resolve(root)?;
    let rendered = render::relay::render(&resolved, env, root)?;
    let mut vars = render::shell::parse_exports(&rendered.exports);

    // Local signing key, when the contributor has generated one.
    let grant_key = relay_dir.join("config/grant/grant_public.pem");
    if let Ok(key) = fs::read_to_string(&grant_key) {
        vars.push(("GRANT_PUBLIC_KEY".into(), key));
    }

    stop_running(root)?;

    println!("→ Building the relay…");
    let status = Command::new("cargo")
        .args(["build", "--manifest-path"])
        .arg(relay_dir.join("Cargo.toml"))
        .status()
        .context("running cargo build")?;
    if !status.success() {
        bail!("relay build failed");
    }

    let log = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(log_file(root))
        .context("opening the relay log")?;

    // Its own process group, so the relay outlives whatever started it, and
    // its own directory, because it resolves config/ relative to the cwd.
    let child = Command::new("./target/debug/eigin-relay")
        .current_dir(&relay_dir)
        .envs(vars.iter().map(|(k, v)| (k.as_str(), v.as_str())))
        .stdout(log.try_clone()?)
        .stderr(log)
        .stdin(std::process::Stdio::null())
        .process_group(0)
        .spawn()
        .context("starting the relay")?;

    fs::write(pid_file(root), format!("{}\n", child.id())).context("writing the pid file")?;

    let port = port_from(&vars);
    if wait_until_serving(port) {
        println!(
            "Relay running ({}) on port {port} → just logs relay --follow",
            env.as_str()
        );
        return Ok(());
    }

    let _ = fs::remove_file(pid_file(root));
    let _ = Command::new("kill").arg(child.id().to_string()).status();
    let log = fs::read_to_string(log_file(root)).unwrap_or_default();
    eprintln!("{}", logs::tail(&log, 20));
    bail!("the relay did not come up on port {port}");
}

/// Stop the relay we started, if it is still running.
pub fn stop(root: &str) -> Result<()> {
    match read_pid(root) {
        Some(pid) if kill(pid, "TERM") => {
            wait_for_exit(pid);
            let _ = fs::remove_file(pid_file(root));
            println!("Relay stopped (pid {pid}).");
        }
        Some(_) => {
            let _ = fs::remove_file(pid_file(root));
            println!("Stale pid file removed; the relay was not running.");
        }
        None => println!("No detached relay running."),
    }
    Ok(())
}

pub fn show_logs(since: Option<Since>, follow: bool, root: &str) -> Result<()> {
    let path = log_file(root);
    if follow {
        let status = Command::new("tail")
            .args(["-n", "50", "-f"])
            .arg(&path)
            .status()
            .context("running tail")?;
        if !status.success() {
            bail!("no relay log yet — run `just run relay`");
        }
        return Ok(());
    }

    let text = logs::read(&path, "run `just run relay`")?;
    match since {
        Some(since) => print!(
            "{}",
            logs::filter_since(&text, &since.cutoff(logs::now_unix()))
        ),
        None => println!("{}", logs::tail(&text, 50)),
    }
    Ok(())
}

fn stop_running(root: &str) -> Result<()> {
    if let Some(pid) = read_pid(root)
        && kill(pid, "TERM")
    {
        wait_for_exit(pid);
    }
    let _ = fs::remove_file(pid_file(root));
    Ok(())
}

fn read_pid(root: &str) -> Option<u32> {
    fs::read_to_string(pid_file(root)).ok()?.trim().parse().ok()
}

fn kill(pid: u32, signal: &str) -> bool {
    Command::new("kill")
        .arg(format!("-{signal}"))
        .arg(pid.to_string())
        .stderr(std::process::Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn wait_for_exit(pid: u32) {
    for _ in 0..40 {
        if !kill(pid, "0") {
            return;
        }
        std::thread::sleep(Duration::from_millis(50));
    }
}

fn port_from(vars: &[(String, String)]) -> u16 {
    vars.iter()
        .find(|(k, _)| k == "PORT")
        .and_then(|(_, v)| v.parse().ok())
        .unwrap_or(DEFAULT_PORT)
}

/// A relay that never accepts a connection is a failed start, however healthy
/// its process looks: a taken port or an unreadable config both end up here.
fn wait_until_serving(port: u16) -> bool {
    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    let deadline = std::time::Instant::now() + READY_TIMEOUT;
    while std::time::Instant::now() < deadline {
        if TcpStream::connect_timeout(&addr, Duration::from_millis(200)).is_ok() {
            return true;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    false
}
