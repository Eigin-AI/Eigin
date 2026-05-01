//! Monthly quota pool for tracking search usage.
//!
//! Tracks the number of searches consumed in the current month and enforces
//! a maximum quota. State is persisted to a JSON file and resets on month rollover.

use std::fs;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use serde::{Deserialize, Serialize};
use time::OffsetDateTime;
use time::macros::format_description;

use crate::error::AppError;

/// Persistent state for the quota pool.
#[derive(Serialize, Deserialize)]
struct PoolState {
    /// Current month in YYYY-MM format.
    month: String,
    /// Number of searches used this month.
    used: u64,
}

/// Monthly quota pool.
///
/// Tracks remaining searches and persists state to disk. Automatically
/// resets when the calendar month changes.
pub struct Pool {
    /// Current pool state (month and usage count).
    state: Mutex<PoolState>,
    /// Maximum searches allowed per month.
    max: u64,
    /// Path to the persisted state file.
    file_path: PathBuf,
}

impl Pool {
    /// Loads a pool from the given file path.
    ///
    /// If the file exists and contains valid state for the current month,
    /// it loads the existing usage count. Otherwise, starts fresh.
    pub fn load(file_path: PathBuf, max: u64) -> Self {
        let current_month = Self::current_month();
        let state = Self::read_state(&file_path, &current_month);

        tracing::info!(
            month = %state.month,
            used = state.used,
            max,
            "pool loaded"
        );

        Self {
            state: Mutex::new(state),
            max,
            file_path,
        }
    }

    /// Attempts to consume one search from the quota.
    ///
    /// Returns `AppError::PoolExhausted` if the monthly limit has been reached.
    /// Automatically resets usage count on month rollover.
    pub fn try_consume(&self) -> Result<(), AppError> {
        let mut state = self.state.lock().unwrap();
        let current_month = Self::current_month();

        // Reset on month rollover
        if state.month != current_month {
            tracing::info!(old = %state.month, new = %current_month, "month rolled over, resetting pool");
            state.month = current_month;
            state.used = 0;
        }

        if state.used >= self.max {
            return Err(AppError::PoolExhausted);
        }

        state.used += 1;
        self.persist(&state);
        Ok(())
    }

    /// Returns the number of searches remaining this month.
    pub fn remaining(&self) -> u64 {
        let state = self.state.lock().unwrap();
        self.max.saturating_sub(state.used)
    }

    fn read_state(path: &Path, current_month: &str) -> PoolState {
        match fs::read_to_string(path) {
            Ok(contents) => match serde_json::from_str::<PoolState>(&contents) {
                Ok(state) if state.month == current_month => state,
                Ok(_) => PoolState {
                    month: current_month.to_string(),
                    used: 0,
                },
                Err(e) => {
                    tracing::warn!("corrupt pool file, resetting: {e}");
                    PoolState {
                        month: current_month.to_string(),
                        used: 0,
                    }
                }
            },
            Err(_) => PoolState {
                month: current_month.to_string(),
                used: 0,
            },
        }
    }

    fn persist(&self, state: &PoolState) {
        let tmp = self.file_path.with_extension("json.tmp");
        let json = serde_json::to_string(state).unwrap();

        if let Err(e) = fs::write(&tmp, &json) {
            tracing::error!("failed to write pool tmp file: {e}");
            return;
        }
        if let Err(e) = fs::rename(&tmp, &self.file_path) {
            tracing::error!("failed to rename pool file: {e}");
        }
    }

    fn current_month() -> String {
        let now = OffsetDateTime::now_utc();
        let fmt = format_description!("[year]-[month]");
        now.format(&fmt).unwrap()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use tempfile::TempDir;

    #[test]
    fn within_quota_allows_request() {
        let tmp = TempDir::new().unwrap();
        let pool = Pool::load(tmp.path().to_path_buf(), 10);

        for _ in 0..10 {
            assert!(pool.try_consume().is_ok());
        }
        assert_eq!(pool.remaining(), 0);
    }

    #[test]
    fn over_quota_rejects_request() {
        let tmp = TempDir::new().unwrap();
        let pool = Pool::load(tmp.path().to_path_buf(), 3);

        for _ in 0..3 {
            pool.try_consume().unwrap();
        }

        assert!(matches!(pool.try_consume(), Err(AppError::PoolExhausted)));
    }

    #[test]
    fn remaining_counts_down() {
        let tmp = TempDir::new().unwrap();
        let pool = Pool::load(tmp.path().to_path_buf(), 10);

        assert_eq!(pool.remaining(), 10);
        pool.try_consume().unwrap();
        assert_eq!(pool.remaining(), 9);
        pool.try_consume().unwrap();
        assert_eq!(pool.remaining(), 8);
    }

    #[test]
    fn load_from_missing_file_starts_at_zero() {
        let tmp = TempDir::new().unwrap();
        let pool = Pool::load(tmp.path().join("nonexistent.json"), 100);

        assert_eq!(pool.remaining(), 100);
    }

    #[test]
    fn load_from_corrupt_file_resets() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("pool.json");
        fs::write(&path, "not valid json {{{").unwrap();

        let pool = Pool::load(path, 100);

        assert_eq!(pool.remaining(), 100);
    }

    #[test]
    fn load_from_old_month_resets() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("pool.json");
        let old_month = "2020-01";
        fs::write(
            &path,
            serde_json::to_string(&PoolState {
                month: old_month.to_string(),
                used: 50,
            })
            .unwrap(),
        )
        .unwrap();

        let pool = Pool::load(path, 100);

        assert_eq!(pool.remaining(), 100);
    }

    #[test]
    fn persist_writes_to_disk() {
        let tmp = TempDir::new().unwrap();
        let path = tmp.path().join("pool.json");
        let pool = Pool::load(path.clone(), 100);

        pool.try_consume().unwrap();
        pool.try_consume().unwrap();

        let contents = fs::read_to_string(&path).unwrap();
        let state: PoolState = serde_json::from_str(&contents).unwrap();

        assert_eq!(state.used, 2);
    }
}
