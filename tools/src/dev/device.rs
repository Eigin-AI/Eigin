use anyhow::{Context, Result, bail};
use serde::Deserialize;
use std::fs;
use std::io::{IsTerminal, Write};
use std::path::PathBuf;
use std::process::Command;

/// A paired iPhone, as both tools that touch it want to name it.
///
/// `xcodebuild -destination` takes the hardware UDID while `devicectl` takes the
/// CoreDevice identifier, and they are different strings for the same phone.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Device {
    pub id: String,
    pub udid: String,
    pub name: String,
}

/// Every paired iPhone CoreDevice knows about.
///
/// devicectl only writes structured output to a file, never to stdout.
pub fn list() -> Result<Vec<Device>> {
    let out = std::env::temp_dir().join(format!("eigin-devices-{}.json", std::process::id()));
    let status = Command::new("xcrun")
        .args(["devicectl", "list", "devices", "--json-output"])
        .arg(&out)
        .stdout(std::process::Stdio::null())
        .status()
        .context("running xcrun devicectl list devices")?;
    if !status.success() {
        bail!("xcrun devicectl list devices failed");
    }
    let json = fs::read_to_string(&out).context("reading devicectl output")?;
    let _ = fs::remove_file(&out);
    parse(&json)
}

#[derive(Deserialize)]
struct Listing {
    result: ListingResult,
}

#[derive(Deserialize)]
struct ListingResult {
    devices: Vec<Entry>,
}

#[derive(Deserialize)]
struct Entry {
    identifier: String,
    #[serde(rename = "deviceProperties")]
    device: DeviceProperties,
    #[serde(rename = "hardwareProperties")]
    hardware: HardwareProperties,
    #[serde(rename = "connectionProperties")]
    connection: ConnectionProperties,
}

#[derive(Deserialize)]
struct DeviceProperties {
    name: String,
}

#[derive(Deserialize)]
struct HardwareProperties {
    udid: String,
    #[serde(rename = "deviceType")]
    device_type: String,
}

#[derive(Deserialize)]
struct ConnectionProperties {
    #[serde(rename = "pairingState")]
    pairing_state: String,
}

fn parse(json: &str) -> Result<Vec<Device>> {
    let listing: Listing = serde_json::from_str(json).context("parsing devicectl output")?;
    Ok(listing
        .result
        .devices
        .into_iter()
        .filter(|d| d.hardware.device_type == "iPhone" && d.connection.pairing_state == "paired")
        .map(|d| Device {
            id: d.identifier,
            udid: d.hardware.udid,
            name: d.device.name,
        })
        .collect())
}

/// Match on either identifier, exactly on name, then on a case-insensitive
/// part of the name, so `"Daniel"` finds `"Daniel's iPhone"`.
pub fn find<'a>(devices: &'a [Device], value: &str) -> Option<&'a Device> {
    devices
        .iter()
        .find(|d| d.id == value || d.udid == value || d.name == value)
        .or_else(|| {
            let needle = value.to_lowercase();
            devices
                .iter()
                .find(|d| d.name.to_lowercase().contains(&needle))
        })
}

/// Which phone to use, given what the caller asked for.
///
/// A name wins, then `$EIGIN_DEVICE`, then the device last used, then the only
/// paired iPhone. Failing all that, ask — but only when someone is there to
/// answer. Everything but `$EIGIN_DEVICE` is remembered for next time, so the
/// session override stays a session override.
pub fn resolve(requested: Option<&str>, interactive: bool, repo_root: &str) -> Result<Device> {
    let devices = list()?;
    if devices.is_empty() {
        bail!(
            "No paired iPhone found. Pair one with Xcode, enable Developer Mode, and keep it unlocked on the same network."
        );
    }

    let env_override = std::env::var("EIGIN_DEVICE").ok().filter(|v| !v.is_empty());
    if let Some(value) = requested {
        let device = find(&devices, value)
            .with_context(|| format!("No paired iPhone matches '{value}'. {}", paired(&devices)))?;
        save_default(repo_root, device)?;
        return Ok(device.clone());
    }
    if let Some(value) = &env_override {
        let device = find(&devices, value).with_context(|| {
            format!(
                "EIGIN_DEVICE='{value}' does not match a paired iPhone. {}",
                paired(&devices)
            )
        })?;
        return Ok(device.clone());
    }
    // A remembered device that is no longer paired falls through to the picker.
    if let Some(cached) = read_default(repo_root)
        && let Some(device) = find(&devices, &cached)
    {
        return Ok(device.clone());
    }

    let device = if devices.len() == 1 {
        devices[0].clone()
    } else if interactive && std::io::stdin().is_terminal() {
        prompt(&devices)?
    } else {
        bail!(
            "Multiple paired iPhones and no saved default. Pass a name or pick one interactively.\n{}",
            paired(&devices)
        );
    };
    save_default(repo_root, &device)?;
    Ok(device)
}

fn prompt(devices: &[Device]) -> Result<Device> {
    eprintln!("Select which iPhone to use (remembered for next time):");
    for (i, device) in devices.iter().enumerate() {
        eprintln!("  {}) {}", i + 1, device.name);
    }
    eprint!("Device [1-{}]: ", devices.len());
    std::io::stderr().flush().ok();

    let mut answer = String::new();
    std::io::stdin()
        .read_line(&mut answer)
        .context("reading the device choice")?;
    let choice: usize = answer
        .trim()
        .parse()
        .ok()
        .filter(|n| (1..=devices.len()).contains(n))
        .with_context(|| format!("Invalid choice: {}", answer.trim()))?;
    Ok(devices[choice - 1].clone())
}

fn paired(devices: &[Device]) -> String {
    let names: Vec<&str> = devices.iter().map(|d| d.name.as_str()).collect();
    format!("Paired: {}", names.join(", "))
}

fn default_file(repo_root: &str) -> PathBuf {
    PathBuf::from(repo_root).join("logs/device-default")
}

fn read_default(repo_root: &str) -> Option<String> {
    fs::read_to_string(default_file(repo_root))
        .ok()
        .map(|v| v.trim().to_string())
        .filter(|v| !v.is_empty())
}

fn save_default(repo_root: &str, device: &Device) -> Result<()> {
    let path = default_file(repo_root);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).context("creating the logs directory")?;
    }
    fs::write(&path, format!("{}\n", device.id)).context("saving the default device")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn devices() -> Vec<Device> {
        vec![
            Device {
                id: "A9D9-CORE".into(),
                udid: "00008120-HW".into(),
                name: "Daniel’s iPhone (2)".into(),
            },
            Device {
                id: "B111-CORE".into(),
                udid: "00008121-HW".into(),
                name: "Test iPhone".into(),
            },
        ]
    }

    #[test]
    fn matches_either_identifier() {
        assert_eq!(
            find(&devices(), "A9D9-CORE").unwrap().name,
            "Daniel’s iPhone (2)"
        );
        assert_eq!(find(&devices(), "00008121-HW").unwrap().name, "Test iPhone");
    }

    #[test]
    fn matches_part_of_a_name_ignoring_case() {
        assert_eq!(find(&devices(), "daniel").unwrap().id, "A9D9-CORE");
        assert_eq!(find(&devices(), "TEST").unwrap().id, "B111-CORE");
    }

    #[test]
    fn an_ambiguous_part_takes_the_first_listed() {
        // "iPhone" is in both names; devicectl's order decides, and the name
        // arg exists for saying which one you meant.
        assert_eq!(find(&devices(), "phone").unwrap().id, "A9D9-CORE");
    }

    #[test]
    fn prefers_an_exact_name_over_a_partial_one() {
        let devices = vec![
            Device {
                id: "1".into(),
                udid: "u1".into(),
                name: "iPhone 15 spare".into(),
            },
            Device {
                id: "2".into(),
                udid: "u2".into(),
                name: "iPhone".into(),
            },
        ];
        assert_eq!(find(&devices, "iPhone").unwrap().id, "2");
    }

    #[test]
    fn no_match_is_none() {
        assert!(find(&devices(), "Nokia").is_none());
    }

    #[test]
    fn keeps_only_paired_iphones() {
        let json = r#"{"result":{"devices":[
            {"identifier":"phone","deviceProperties":{"name":"My iPhone"},
             "hardwareProperties":{"udid":"hw1","deviceType":"iPhone"},
             "connectionProperties":{"pairingState":"paired"}},
            {"identifier":"pad","deviceProperties":{"name":"My iPad"},
             "hardwareProperties":{"udid":"hw2","deviceType":"iPad"},
             "connectionProperties":{"pairingState":"paired"}},
            {"identifier":"unpaired","deviceProperties":{"name":"Other iPhone"},
             "hardwareProperties":{"udid":"hw3","deviceType":"iPhone"},
             "connectionProperties":{"pairingState":"unpaired"}}
        ]}}"#;
        let devices = parse(json).unwrap();
        assert_eq!(devices.len(), 1);
        assert_eq!(devices[0].name, "My iPhone");
        assert_eq!(devices[0].udid, "hw1");
    }
}
