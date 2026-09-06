//! The web gallery: Vite dev server run detached, like the relay.

use anyhow::{Context, Result, bail};
use std::fs;
use std::io::Write as _;
use std::net::{SocketAddr, TcpStream};
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::Command;
use std::time::Duration;

use super::logs::{self, Since};

const DEFAULT_PORT: u16 = 5173;
const READY_TIMEOUT: Duration = Duration::from_secs(60);
const WEB_DIR: &str = "design/web";

fn log_file(root: &str) -> PathBuf {
    PathBuf::from(root).join("logs/web.log")
}

fn pid_file(root: &str) -> PathBuf {
    PathBuf::from(root).join("logs/web.pid")
}

fn web_dir(root: &str) -> PathBuf {
    PathBuf::from(root).join(WEB_DIR)
}

/// Install node_modules when they're missing, so a fresh checkout just works.
fn ensure_dependencies(root: &str) -> Result<()> {
    if web_dir(root).join("node_modules/.bin/vite").exists() {
        return Ok(());
    }
    println!("→ Installing web dependencies (npm install)…");
    let status = Command::new("npm")
        .args(["install", "--no-fund", "--no-audit"])
        .current_dir(web_dir(root))
        .status()
        .context("running npm install")?;
    if !status.success() {
        bail!("npm install failed");
    }
    Ok(())
}

/// Start the gallery dev server, detached, replacing an instance we started before.
pub fn start(root: &str) -> Result<()> {
    if !web_dir(root).exists() {
        bail!("no {WEB_DIR} — the gallery is not checked out");
    }
    fs::create_dir_all(PathBuf::from(root).join("logs")).context("creating the logs directory")?;

    ensure_dependencies(root)?;

    // Fresh tokens before the server starts. The web target is in-process —
    // running full codegen (localize, xcodegen, build server) would be
    // far too slow for a dev-server start.
    let tokens = crate::design::tokens::load_tokens(root)?;
    let installed = crate::design::ios::fonts::install(root, &tokens)?;
    crate::design::web::generate(root, &tokens, installed.as_ref())
        .context("generating web tokens")?;

    stop_running(root)?;

    let log = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(log_file(root))
        .context("opening the web log")?;

    // Its own process group, so the server outlives whatever started it.
    let mut command = Command::new("npm");
    command
        .args([
            "run",
            "dev",
            "--",
            "--port",
            &DEFAULT_PORT.to_string(),
            "--strictPort",
        ])
        .current_dir(web_dir(root))
        .stdout(log.try_clone()?)
        .stderr(log)
        .stdin(std::process::Stdio::null())
        .process_group(0);
    let child = command.spawn().context("starting the web dev server")?;

    fs::write(pid_file(root), format!("{}\n", child.id())).context("writing the pid file")?;

    if wait_until_serving(DEFAULT_PORT) {
        let _ = std::io::stdout().flush();
        println!("Gallery running at http://localhost:{DEFAULT_PORT} → just logs web --follow");
        let _ = std::io::stdout().flush();
        return Ok(());
    }

    let _ = fs::remove_file(pid_file(root));
    let _ = Command::new("kill").arg(child.id().to_string()).status();
    let log = fs::read_to_string(log_file(root)).unwrap_or_default();
    eprintln!("{}", logs::tail(&log, 20));
    bail!("the web dev server did not come up on port {DEFAULT_PORT}");
}

/// Stop the gallery we started, if it is still running.
pub fn stop(root: &str) -> Result<()> {
    match read_pid(root) {
        Some(pid) if kill(pid, "TERM") => {
            wait_for_exit(pid);
            let _ = fs::remove_file(pid_file(root));
            println!("Gallery stopped (pid {pid}).");
        }
        Some(_) => {
            let _ = fs::remove_file(pid_file(root));
            println!("Stale pid file removed; the gallery was not running.");
        }
        None => println!("No detached gallery running."),
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
            bail!("no web log yet — run `just run web`");
        }
        return Ok(());
    }

    let text = logs::read(&path, "run `just run web`")?;
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

/// A server that never accepts a connection is a failed start: a taken port
/// or a missing npm both end up here. Vite binds whichever loopback stack it
/// likes (often ::1), so probe both.
fn wait_until_serving(port: u16) -> bool {
    let addrs = [
        SocketAddr::from(([127, 0, 0, 1], port)),
        SocketAddr::from(([0, 0, 0, 0, 0, 0, 0, 1], port)),
    ];
    let deadline = std::time::Instant::now() + READY_TIMEOUT;
    while std::time::Instant::now() < deadline {
        if addrs
            .iter()
            .any(|addr| TcpStream::connect_timeout(addr, Duration::from_millis(200)).is_ok())
        {
            return true;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    false
}
