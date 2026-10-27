//! The web surfaces: Vite dev server run detached, like the relay.

use anyhow::{Context, Result, bail};
use std::fs;
use std::io::Write as _;
use std::net::{SocketAddr, TcpStream};
use std::os::unix::process::CommandExt;
use std::path::PathBuf;
use std::process::Command;
use std::time::Duration;

use super::logs::{self, Since};

/// Independently runnable web surfaces.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum WebTarget {
    Gallery,
    Site,
}

impl WebTarget {
    fn port(self) -> u16 {
        match self {
            Self::Gallery => 5173,
            Self::Site => 5174,
        }
    }
    fn directory(self) -> &'static str {
        match self {
            Self::Gallery => "design/web",
            Self::Site => "src/eigin_website",
        }
    }
    fn workspace(self) -> &'static str {
        match self {
            Self::Gallery => "@eigin/ui",
            Self::Site => "@eigin/website",
        }
    }
    fn identity(self) -> &'static str {
        match self {
            Self::Gallery => "web",
            Self::Site => "website",
        }
    }
}

/// Parse an optional web surface selector; empty means gallery.
pub fn parse(args: &[String]) -> Result<WebTarget> {
    let args: Vec<_> = args.iter().filter(|a| !a.is_empty()).collect();
    match args.as_slice() {
        [] => Ok(WebTarget::Gallery),
        [value] if value.as_str() == "gallery" => Ok(WebTarget::Gallery),
        [value] if value.as_str() == "site" => Ok(WebTarget::Site),
        _ => bail!("Expected web [gallery | site]"),
    }
}
const READY_TIMEOUT: Duration = Duration::from_secs(60);

fn log_file(root: &str, target: WebTarget) -> PathBuf {
    PathBuf::from(root).join(format!("logs/{}.log", target.identity()))
}

fn pid_file(root: &str, target: WebTarget) -> PathBuf {
    PathBuf::from(root).join(format!("logs/{}.pid", target.identity()))
}

fn web_dir(root: &str, target: WebTarget) -> PathBuf {
    PathBuf::from(root).join(target.directory())
}

/// Install node_modules when they're missing, so a fresh checkout just works.
fn ensure_dependencies(root: &str) -> Result<()> {
    if PathBuf::from(root).join("node_modules/.bin/vite").exists() {
        return Ok(());
    }
    println!("→ Installing web dependencies (npm install)…");
    let status = Command::new("npm")
        .args(["install", "--no-fund", "--no-audit"])
        .current_dir(root)
        .status()
        .context("running npm install")?;
    if !status.success() {
        bail!("npm install failed");
    }
    Ok(())
}

/// Start a web dev server, replacing the tracked instance for this surface.
pub fn start(root: &str, target: WebTarget) -> Result<()> {
    if !web_dir(root, target).exists() {
        bail!(
            "no {} — the web surface is not checked out",
            target.directory()
        );
    }
    fs::create_dir_all(PathBuf::from(root).join("logs")).context("creating the logs directory")?;

    ensure_dependencies(root)?;

    // Fresh tokens before the server starts. The web target is in-process —
    // running full codegen (localize, xcodegen, build server) would be
    // far too slow for a dev-server start.
    crate::design::web::generate_assets(root)?;

    stop_running(root, target)?;
    reclaim_port(target.port(), root, target)?;

    let log = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(log_file(root, target))
        .context("opening the web log")?;

    // Its own process group, so the server outlives whatever started it.
    let mut command = Command::new("npm");
    command
        .args([
            "run",
            "dev",
            "--workspace",
            target.workspace(),
            "--",
            "--port",
            &target.port().to_string(),
            "--strictPort",
        ])
        .current_dir(root)
        .stdout(log.try_clone()?)
        .stderr(log)
        .stdin(std::process::Stdio::null())
        .process_group(0);
    let child = command.spawn().context("starting the web dev server")?;

    fs::write(pid_file(root, target), format!("{}\n", child.id()))
        .context("writing the pid file")?;

    if wait_until_serving(target.port()) {
        let _ = std::io::stdout().flush();
        println!(
            "Web {:?} running at http://localhost:{}",
            target,
            target.port()
        );
        let _ = std::io::stdout().flush();
        return Ok(());
    }

    let _ = fs::remove_file(pid_file(root, target));
    let _ = Command::new("kill")
        .args(["-TERM", "--", &format!("-{}", child.id())])
        .status();
    let log = fs::read_to_string(log_file(root, target)).unwrap_or_default();
    eprintln!("{}", logs::tail(&log, 20));
    bail!(
        "the web dev server did not come up on port {}",
        target.port()
    );
}

/// Stop the tracked web surface, if it is still running.
pub fn stop(root: &str, target: WebTarget) -> Result<()> {
    stop_running(root, target)?;
    println!("Web {:?} stopped.", target);
    Ok(())
}

pub fn show_logs(since: Option<Since>, follow: bool, root: &str, target: WebTarget) -> Result<()> {
    let path = log_file(root, target);
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

/// Reclaim this checkout's matching Vite process; refuse unrelated listeners.
fn reclaim_port(port: u16, root: &str, target: WebTarget) -> Result<()> {
    for pid in listeners(port) {
        let command = process_command(pid);
        if !is_server(&command, root, target) {
            bail!("port {port} is held by pid {pid} ({command}) — stop it and try again");
        }
        println!("→ Reclaiming port {port} from a stale web server (pid {pid})…");
        if kill(pid, "TERM") {
            wait_for_exit(pid);
        }
    }
    Ok(())
}

/// Match both the checkout and target port before reclaiming a listener.
fn is_server(command: &str, root: &str, target: WebTarget) -> bool {
    let executables = [
        format!("{root}/node_modules/.bin/vite"),
        format!("{root}/{}/node_modules/.bin/vite", target.directory()),
    ];
    executables
        .iter()
        .any(|path| command.contains(&format!(" {path} ")))
        && command.ends_with(&format!("--port {} --strictPort", target.port()))
}

fn listeners(port: u16) -> Vec<u32> {
    let Ok(output) = Command::new("lsof")
        .args(["-ti", &format!("tcp:{port}"), "-sTCP:LISTEN"])
        .stderr(std::process::Stdio::null())
        .output()
    else {
        return Vec::new();
    };
    String::from_utf8_lossy(&output.stdout)
        .lines()
        .filter_map(|line| line.trim().parse().ok())
        .collect()
}

fn process_command(pid: u32) -> String {
    Command::new("ps")
        .args(["-o", "command=", "-p", &pid.to_string()])
        .output()
        .ok()
        .map(|out| String::from_utf8_lossy(&out.stdout).trim().to_string())
        .filter(|command| !command.is_empty())
        .unwrap_or_else(|| "unknown".to_string())
}

fn stop_running(root: &str, target: WebTarget) -> Result<()> {
    if let Some(pid) = read_pid(root, target) {
        let command = process_command(pid);
        if command != "unknown" {
            let cwd = Command::new("lsof")
                .args(["-a", "-p", &pid.to_string(), "-d", "cwd", "-Fn"])
                .output()
                .context("checking web process directory")?;
            let owned = String::from_utf8_lossy(&cwd.stdout)
                .lines()
                .any(|line| line == format!("n{root}"));
            if !owned
                || !command.starts_with("npm run dev ")
                || !command.contains(&format!("--port {} --strictPort", target.port()))
            {
                bail!("pid {pid} no longer belongs to this web target — refusing to stop it");
            }
            // The detached npm process owns the whole server process group.
            let status = Command::new("kill")
                .args(["-TERM", "--", &format!("-{pid}")])
                .status()?;
            if !status.success() {
                bail!("could not stop web process group {pid}");
            }
            wait_for_exit(pid);
        }
    }
    let _ = fs::remove_file(pid_file(root, target));
    Ok(())
}

fn read_pid(root: &str, target: WebTarget) -> Option<u32> {
    fs::read_to_string(pid_file(root, target))
        .ok()?
        .trim()
        .parse()
        .ok()
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

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn selectors_are_explicit() {
        assert_eq!(parse(&[]).unwrap(), WebTarget::Gallery);
        assert_eq!(parse(&["site".into()]).unwrap(), WebTarget::Site);
        assert!(parse(&["app".into()]).is_err());
        assert!(parse(&["site".into(), "production".into()]).is_err());
    }
    #[test]
    fn reclaims_workspace_vite_only_for_its_checkout_and_target() {
        for (target, sibling) in [
            (WebTarget::Site, WebTarget::Gallery),
            (WebTarget::Gallery, WebTarget::Site),
        ] {
            let command = format!(
                "node /repo/{}/node_modules/.bin/vite --port {} --strictPort",
                target.directory(),
                target.port()
            );
            assert!(is_server(&command, "/repo", target));
            assert!(!is_server(&command, "/other", target));
            assert!(!is_server(&command, "/repo", sibling));
            let wrong_workspace = format!(
                "node /repo/{}/node_modules/.bin/vite --port {} --strictPort",
                sibling.directory(),
                target.port()
            );
            assert!(!is_server(&wrong_workspace, "/repo", target));
            let prefixed_checkout = command.replace("/repo/", "/other/repo/");
            assert!(!is_server(&prefixed_checkout, "/repo", target));
            let wrong_executable = command.replace("/.bin/vite ", "/.bin/vite-unrelated ");
            assert!(!is_server(&wrong_executable, "/repo", target));
        }
    }

    #[test]
    fn only_reclaims_our_target() {
        let command = "node /repo/node_modules/.bin/vite --port 5174 --strictPort";
        assert!(is_server(command, "/repo", WebTarget::Site));
        assert!(!is_server(command, "/repo", WebTarget::Gallery));
        assert!(!is_server(command, "/other", WebTarget::Site));
        assert!(!is_server(
            "python -m http.server 5174",
            "/repo",
            WebTarget::Site
        ));
    }
}
