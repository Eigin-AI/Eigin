use anyhow::{Context, Result, bail};

/// How far back to read. A duration counts back from now; a date is used as
/// written, so `2026-09-02` means everything logged that day onwards.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Since(String);

impl Since {
    /// The default window: recent enough to be the run you just did.
    pub const DEFAULT: &'static str = "10m";

    /// Whether a bare argument is a window, used to tell `2h` from a device name.
    pub fn looks_like(value: &str) -> bool {
        is_date(value) || duration_seconds(value).is_some()
    }

    pub fn parse(value: &str) -> Result<Since> {
        if !Self::looks_like(value) {
            bail!("Invalid window: {value} (use 30s, 10m, 2h, 7d, or a date like 2026-09-02)");
        }
        Ok(Since(value.to_string()))
    }

    /// The oldest timestamp to keep, as an ISO string. Timestamps sort
    /// lexicographically, so comparing strings is comparing times.
    pub fn cutoff(&self, now_unix: i64) -> String {
        if is_date(&self.0) {
            return self.0.clone();
        }
        let seconds = duration_seconds(&self.0).unwrap_or(0);
        iso_utc(now_unix - seconds)
    }

    /// The form `log show` wants: a duration it counts back itself, or a start date.
    pub fn as_log_show_args(&self) -> Vec<String> {
        if is_date(&self.0) {
            vec!["--start".into(), self.0.clone()]
        } else {
            vec!["--last".into(), self.0.clone()]
        }
    }
}

fn is_date(value: &str) -> bool {
    let bytes = value.as_bytes();
    bytes.len() >= 10
        && bytes[..4].iter().all(u8::is_ascii_digit)
        && bytes[4] == b'-'
        && bytes[5..7].iter().all(u8::is_ascii_digit)
        && bytes[7] == b'-'
        && bytes[8..10].iter().all(u8::is_ascii_digit)
}

fn duration_seconds(value: &str) -> Option<i64> {
    let (digits, unit) = value.split_at(value.len().checked_sub(1)?);
    let count: i64 = digits.parse().ok()?;
    let multiplier = match unit {
        "s" => 1,
        "m" => 60,
        "h" => 3600,
        "d" => 86400,
        _ => return None,
    };
    Some(count * multiplier)
}

/// Keep the lines at or after `cutoff`.
///
/// The timestamp is found anywhere in the line, because the relay colours its
/// output and the escape codes come first. Lines without one — stack traces and
/// other continuations — stay with the entry above them.
pub fn filter_since(text: &str, cutoff: &str) -> String {
    let mut out = String::new();
    let mut keeping = false;
    for line in text.lines() {
        if let Some(stamp) = timestamp_in(line) {
            keeping = stamp >= cutoff;
        }
        if keeping {
            out.push_str(line);
            out.push('\n');
        }
    }
    out
}

/// The first `YYYY-MM-DDTHH:MM:SS` in a line.
fn timestamp_in(line: &str) -> Option<&str> {
    let bytes = line.as_bytes();
    (0..bytes.len().saturating_sub(18)).find_map(|i| {
        let candidate = line.get(i..i + 19)?;
        is_timestamp(candidate).then_some(candidate)
    })
}

fn is_timestamp(value: &str) -> bool {
    let b = value.as_bytes();
    is_date(value)
        && b.len() == 19
        && b[10] == b'T'
        && b[11..13].iter().all(u8::is_ascii_digit)
        && b[13] == b':'
        && b[14..16].iter().all(u8::is_ascii_digit)
        && b[16] == b':'
        && b[17..19].iter().all(u8::is_ascii_digit)
}

pub fn now_unix() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or_default()
}

/// Format a Unix timestamp as `YYYY-MM-DDTHH:MM:SS` in UTC.
///
/// Log timestamps are UTC, so the cutoff has to be too. Days are converted with
/// the civil-from-days algorithm, shifting the year to start in March so leap
/// days land at the end of the cycle.
fn iso_utc(unix: i64) -> String {
    let days = unix.div_euclid(86_400);
    let seconds = unix.rem_euclid(86_400);

    let z = days + 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = yoe + era * 400 + i64::from(month <= 2);

    format!(
        "{year:04}-{month:02}-{day:02}T{:02}:{:02}:{:02}",
        seconds / 3600,
        (seconds % 3600) / 60,
        seconds % 60
    )
}

/// Read a log file, or explain that there isn't one yet.
pub fn read(path: &std::path::Path, hint: &str) -> Result<String> {
    std::fs::read_to_string(path).with_context(|| format!("No log yet — {hint}."))
}

/// The last `count` lines, for when no window was asked for.
pub fn tail(text: &str, count: usize) -> String {
    let lines: Vec<&str> = text.lines().collect();
    let start = lines.len().saturating_sub(count);
    lines[start..].join("\n")
}

#[cfg(test)]
mod tests {
    use super::*;

    // 2026-09-02T18:39:10Z
    const NOW: i64 = 1_788_374_350;

    #[test]
    fn durations_count_back_from_now() {
        assert_eq!(
            Since::parse("1h").unwrap().cutoff(NOW),
            "2026-09-02T17:39:10"
        );
        assert_eq!(
            Since::parse("30s").unwrap().cutoff(NOW),
            "2026-09-02T18:38:40"
        );
        assert_eq!(
            Since::parse("2d").unwrap().cutoff(NOW),
            "2026-08-31T18:39:10"
        );
    }

    #[test]
    fn a_date_is_the_cutoff_as_written() {
        assert_eq!(
            Since::parse("2026-09-02").unwrap().cutoff(NOW),
            "2026-09-02"
        );
    }

    #[test]
    fn leap_days_survive_the_conversion() {
        // 2024-02-29T12:00:00Z
        assert_eq!(iso_utc(1_709_208_000), "2024-02-29T12:00:00");
    }

    #[test]
    fn rejects_things_that_are_not_windows() {
        for value in ["1234", "banana", "staging", "10", "2026-99"] {
            assert!(!Since::looks_like(value), "{value} should not parse");
            assert!(Since::parse(value).is_err());
        }
    }

    #[test]
    fn log_show_gets_a_duration_or_a_start_date() {
        assert_eq!(
            Since::parse("10m").unwrap().as_log_show_args(),
            ["--last", "10m"]
        );
        assert_eq!(
            Since::parse("2026-09-02").unwrap().as_log_show_args(),
            ["--start", "2026-09-02"]
        );
    }

    #[test]
    fn keeps_only_entries_at_or_after_the_cutoff() {
        let log = "2026-09-02T10:00:00.000Z [INFO] old\n\
                   2026-09-02T12:00:00.000Z [INFO] new\n";
        let kept = filter_since(log, "2026-09-02T11:00:00");
        assert!(!kept.contains("old"));
        assert!(kept.contains("new"));
    }

    #[test]
    fn finds_the_timestamp_behind_colour_codes() {
        let log = "\u{1b}[2m2026-09-02T12:00:00.000Z\u{1b}[0m INFO relay started\n";
        assert_eq!(filter_since(log, "2026-09-02T11:00:00"), log);
        assert_eq!(filter_since(log, "2026-09-02T13:00:00"), "");
    }

    #[test]
    fn continuation_lines_follow_their_entry() {
        let log = "2026-09-02T10:00:00.000Z [ERROR] old\n\
                       at old_frame\n\
                   2026-09-02T12:00:00.000Z [ERROR] new\n\
                       at new_frame\n";
        let kept = filter_since(log, "2026-09-02T11:00:00");
        assert!(!kept.contains("old_frame"));
        assert!(kept.contains("new_frame"));
    }

    #[test]
    fn tail_takes_the_end() {
        assert_eq!(tail("a\nb\nc\n", 2), "b\nc");
        assert_eq!(tail("a\n", 5), "a");
    }
}
