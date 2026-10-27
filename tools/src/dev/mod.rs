//! The dev loop: start a target, read its logs, stop it.
//!
//! `run` is fire-and-forget for every target — it returns once the target is up,
//! and `logs` is where output shows up. The iOS app runs on a simulator or a
//! paired phone; the relay runs here, detached.

use anyhow::{Result, bail};

mod device;
mod ios;
mod logs;
mod relay;
mod web;

use crate::config::model::Env;
use logs::Since;

/// Start a target: `relay [env]`, `ios simulator [env]`, `ios device [name] [env]`, `web`.
#[derive(clap::Args)]
pub struct RunArgs {
    /// relay | ios | web
    target: String,
    /// Mode for ios (simulator | device), then a device name and environment.
    args: Vec<String>,
}

/// Stop a detached target.
#[derive(clap::Args)]
pub struct StopArgs {
    /// relay | web
    target: String,
    /// Web surface: gallery | site.
    args: Vec<String>,
}

/// Show a target's logs.
#[derive(clap::Args)]
pub struct LogsArgs {
    /// relay | ios | web
    target: String,
    /// Mode for ios (simulator | device), then a device name, environment and window.
    args: Vec<String>,
    /// How far back to read: 30s, 10m, 2h, 7d, or a date like 2026-09-02.
    #[arg(long)]
    since: Option<String>,
    /// Keep streaming. Simulator and relay only.
    #[arg(long)]
    follow: bool,
}

/// What the loose arguments after a target turned out to mean.
///
/// Recipes pass fixed positional slots, so arguments are recognised by shape
/// rather than order: `logs ios device 2h` and `logs ios device "Daniel" 2h`
/// both work, and neither reads a window as a phone.
#[derive(Debug, Default, PartialEq, Eq)]
struct Slots {
    env: Option<Env>,
    since: Option<String>,
    name: Option<String>,
}

/// What a command accepts after its target, so the error can say so.
#[derive(Clone, Copy)]
struct Accepts {
    name: bool,
    since: bool,
}

impl Accepts {
    fn expected(&self) -> String {
        let mut kinds = vec!["an environment"];
        if self.since {
            kinds.push("a window like 10m");
        }
        if self.name {
            kinds.push("a device name");
        }
        kinds.join(", ")
    }
}

fn classify(args: &[String], accepts: Accepts) -> Result<Slots> {
    let mut slots = Slots::default();
    for arg in args.iter().filter(|a| !a.is_empty()) {
        match arg.as_str() {
            "staging" | "production" => {
                if slots.env.is_some() {
                    bail!("Repeated environment: {arg}");
                }
                slots.env = Some(parse_env(arg)?);
            }
            _ if accepts.since && Since::looks_like(arg) => {
                if slots.since.is_some() {
                    bail!("Repeated window: {arg}");
                }
                slots.since = Some(arg.clone());
            }
            _ if accepts.name && slots.name.is_none() => slots.name = Some(arg.clone()),
            _ => bail!(
                "Unrecognised argument: {arg} (expected {})",
                accepts.expected()
            ),
        }
    }
    Ok(slots)
}

fn parse_env(value: &str) -> Result<Env> {
    match value {
        "staging" => Ok(Env::Staging),
        "production" => Ok(Env::Production),
        _ => bail!("Unknown environment: {value} (use staging | production)"),
    }
}

/// Split an optional leading `simulator`/`device` off the rest.
fn split_mode(args: &[String]) -> (Option<&str>, &[String]) {
    match args.iter().find(|a| !a.is_empty()).map(String::as_str) {
        Some(mode @ ("simulator" | "device")) => {
            let rest = args
                .split_at(args.iter().position(|a| a == mode).unwrap() + 1)
                .1;
            (Some(mode), rest)
        }
        _ => (None, args),
    }
}

pub fn run(args: RunArgs) -> Result<()> {
    let root = crate::config::repo_root()?;
    match args.target.as_str() {
        "relay" => {
            let slots = classify(
                &args.args,
                Accepts {
                    name: false,
                    since: false,
                },
            )?;
            relay::start(slots.env.unwrap_or(Env::Staging), &root)
        }
        "ios" => {
            let (mode, rest) = split_mode(&args.args);
            let Some(mode) = mode else {
                bail!(
                    "Missing ios mode. Use: just run ios simulator [env] | just run ios device [device] [env]"
                );
            };
            let slots = classify(
                rest,
                Accepts {
                    name: mode == "device",
                    since: false,
                },
            )?;
            let env = slots.env.unwrap_or(Env::Staging);
            match mode {
                "simulator" => ios::run_simulator(env, &root),
                _ => ios::run_device(slots.name.as_deref(), env, &root),
            }
        }
        "web" => web::start(&root, web::parse(&args.args)?),
        other => bail!("Unknown run target: {other} (use relay | ios | web)"),
    }
}

pub fn stop(args: StopArgs) -> Result<()> {
    let root = crate::config::repo_root()?;
    match args.target.as_str() {
        "relay" => relay::stop(&root),
        "web" => web::stop(&root, web::parse(&args.args)?),
        other => bail!("Unknown stop target: {other} (use relay | web)"),
    }
}

pub fn logs(args: LogsArgs) -> Result<()> {
    let root = crate::config::repo_root()?;
    if args.target == "web" {
        let selectors: Vec<_> = args
            .args
            .iter()
            .filter(|a| !Since::looks_like(a))
            .cloned()
            .collect();
        let windows: Vec<_> = args.args.iter().filter(|a| Since::looks_like(a)).collect();
        if windows.len() > 1 {
            bail!("Repeated log window");
        }
        let target = web::parse(&selectors)?;
        let since = args
            .since
            .filter(|s| !s.is_empty())
            .or_else(|| windows.first().map(|s| (*s).clone()))
            .map(|s| Since::parse(&s))
            .transpose()?;
        return web::show_logs(since, args.follow, &root, target);
    }
    let (mode, rest) = split_mode(&args.args);
    let slots = classify(
        rest,
        Accepts {
            name: mode == Some("device"),
            since: true,
        },
    )?;
    let since = args
        .since
        .filter(|s| !s.is_empty())
        .or(slots.since)
        .map(|s| Since::parse(&s))
        .transpose()?;

    match args.target.as_str() {
        "relay" => {
            if slots.env.is_some() {
                bail!("just logs relay reads one log file, so it takes no environment");
            }
            if let Some(name) = slots.name {
                bail!("Unrecognised argument: {name}");
            }
            relay::show_logs(since, args.follow, &root)
        }
        "ios" => {
            let env = slots.env.unwrap_or(Env::Staging);
            let since = since.unwrap_or(Since::parse(Since::DEFAULT)?);
            match mode {
                Some("device") => {
                    ios::device_logs(slots.name.as_deref(), env, &since, args.follow, &root)
                }
                _ => ios::simulator_logs(env, &since, args.follow, &root),
            }
        }
        other => bail!("Unknown logs target: {other} (use relay | ios | web)"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn args(values: &[&str]) -> Vec<String> {
        values.iter().map(|v| v.to_string()).collect()
    }

    const FOR_LOGS: Accepts = Accepts {
        name: true,
        since: true,
    };
    const FOR_RUN: Accepts = Accepts {
        name: true,
        since: false,
    };

    #[test]
    fn recognises_arguments_in_any_order() {
        let by_name = classify(&args(&["Daniel", "production", "2h"]), FOR_LOGS).unwrap();
        let by_window = classify(&args(&["2h", "Daniel", "production"]), FOR_LOGS).unwrap();
        assert_eq!(by_name, by_window);
        assert_eq!(by_name.name.as_deref(), Some("Daniel"));
        assert_eq!(by_name.env, Some(Env::Production));
        assert_eq!(by_name.since.as_deref(), Some("2h"));
    }

    #[test]
    fn a_window_is_never_taken_for_a_device() {
        let slots = classify(&args(&["2h"]), FOR_LOGS).unwrap();
        assert_eq!(slots.since.as_deref(), Some("2h"));
        assert_eq!(slots.name, None);
    }

    /// `run` has no window, so a phone may legitimately be called "2h".
    #[test]
    fn without_windows_a_duration_is_a_name() {
        let slots = classify(&args(&["2h"]), FOR_RUN).unwrap();
        assert_eq!(slots.name.as_deref(), Some("2h"));
        assert_eq!(slots.since, None);
    }

    #[test]
    fn empty_slots_are_ignored() {
        // Recipes pass every positional slot, filled or not.
        assert_eq!(
            classify(&args(&["", "", ""]), FOR_LOGS).unwrap(),
            Slots::default()
        );
    }

    #[test]
    fn rejects_repeats_and_unknowns() {
        assert!(classify(&args(&["staging", "production"]), FOR_LOGS).is_err());
        assert!(classify(&args(&["2h", "30m"]), FOR_LOGS).is_err());
        assert!(
            classify(
                &args(&["nonsense"]),
                Accepts {
                    name: false,
                    since: false
                }
            )
            .is_err()
        );
        assert!(classify(&args(&["one", "two"]), FOR_LOGS).is_err());
    }

    #[test]
    fn the_error_names_what_would_have_worked() {
        let err = classify(
            &args(&["nightly"]),
            Accepts {
                name: false,
                since: false,
            },
        )
        .unwrap_err()
        .to_string();
        assert!(err.contains("expected an environment"), "{err}");
        assert!(!err.contains("window"), "{err}");
    }

    #[test]
    fn mode_is_optional_and_only_leads() {
        let with_mode = args(&["device", "Daniel"]);
        let (mode, rest) = split_mode(&with_mode);
        assert_eq!(mode, Some("device"));
        assert_eq!(rest, args(&["Daniel"]));

        let without_mode = args(&["staging"]);
        let (mode, rest) = split_mode(&without_mode);
        assert_eq!(mode, None);
        assert_eq!(rest, args(&["staging"]));
    }
}
