//! In-memory rolling-window quota for dev and tests.
//!
//! State is lost on restart, so this is not for production use. It mirrors the
//! durable Postgres quota's semantics: per-key daily buckets, summed over the
//! trailing window, with buckets outside the window dropped.

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::Duration;

use async_trait::async_trait;
use time::{Date, OffsetDateTime};

use super::bucket::window_bounds;
use super::{Quota, QuotaError};

#[derive(Default)]
pub struct InMemoryQuota {
    buckets: Mutex<HashMap<String, HashMap<Date, u64>>>,
}

impl InMemoryQuota {
    /// Consume against the window ending at `now`. The trait method calls this
    /// with the real clock; tests pass a fixed `now` to exercise day rollover.
    fn try_consume_at(
        &self,
        key: &str,
        amount: u64,
        max: u64,
        window: Duration,
        now: OffsetDateTime,
    ) -> Result<(), QuotaError> {
        let (today, cutoff) = window_bounds(window, now);
        let mut map = self.buckets.lock().unwrap();
        let days = map.entry(key.to_owned()).or_default();
        days.retain(|&d, _| d >= cutoff);

        let used: u64 = days.values().sum();
        if used + amount > max {
            if days.is_empty() {
                map.remove(key);
            }
            return Err(QuotaError::Exhausted);
        }

        *days.entry(today).or_default() += amount;
        Ok(())
    }

    fn remaining_at(&self, key: &str, max: u64, window: Duration, now: OffsetDateTime) -> u64 {
        let (_, cutoff) = window_bounds(window, now);
        let mut map = self.buckets.lock().unwrap();
        let used = match map.get_mut(key) {
            Some(days) => {
                days.retain(|&d, _| d >= cutoff);
                days.values().sum()
            }
            None => 0,
        };
        max.saturating_sub(used)
    }
}

#[async_trait]
impl Quota for InMemoryQuota {
    async fn try_consume(
        &self,
        key: &str,
        amount: u64,
        max: u64,
        window: Duration,
    ) -> Result<(), QuotaError> {
        self.try_consume_at(key, amount, max, window, OffsetDateTime::now_utc())
    }

    async fn remaining(&self, key: &str, max: u64, window: Duration) -> Result<u64, QuotaError> {
        Ok(self.remaining_at(key, max, window, OffsetDateTime::now_utc()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const WINDOW: Duration = Duration::from_secs(30 * 24 * 60 * 60);

    fn day(n: i64) -> OffsetDateTime {
        OffsetDateTime::UNIX_EPOCH + time::Duration::days(20_000 + n)
    }

    #[test]
    fn consumes_up_to_max_then_rejects() {
        let quota = InMemoryQuota::default();
        let now = day(0);
        for _ in 0..10 {
            quota.try_consume_at("k", 1, 10, WINDOW, now).unwrap();
        }
        assert!(matches!(
            quota.try_consume_at("k", 1, 10, WINDOW, now),
            Err(QuotaError::Exhausted)
        ));
    }

    #[test]
    fn amount_weighted_rejects_when_over() {
        let quota = InMemoryQuota::default();
        let now = day(0);
        quota.try_consume_at("k", 400, 1000, WINDOW, now).unwrap();
        quota.try_consume_at("k", 500, 1000, WINDOW, now).unwrap();
        // 900 + 200 > 1000 → rejected, and nothing recorded.
        assert!(matches!(
            quota.try_consume_at("k", 200, 1000, WINDOW, now),
            Err(QuotaError::Exhausted)
        ));
        assert_eq!(quota.remaining_at("k", 1000, WINDOW, now), 100);
    }

    #[test]
    fn keys_are_independent() {
        let quota = InMemoryQuota::default();
        let now = day(0);
        quota.try_consume_at("a", 10, 10, WINDOW, now).unwrap();
        quota.try_consume_at("b", 10, 10, WINDOW, now).unwrap();
        assert_eq!(quota.remaining_at("a", 10, WINDOW, now), 0);
        assert_eq!(quota.remaining_at("b", 10, WINDOW, now), 0);
    }

    #[test]
    fn buckets_age_out_of_window() {
        let quota = InMemoryQuota::default();
        // A 2-day window: today and yesterday count; older days do not.
        let window = Duration::from_secs(2 * 24 * 60 * 60);
        quota.try_consume_at("k", 10, 10, window, day(0)).unwrap();
        assert!(matches!(
            quota.try_consume_at("k", 1, 10, window, day(1)),
            Err(QuotaError::Exhausted)
        ));
        // Two days on, the original day has aged out — headroom returns.
        quota.try_consume_at("k", 10, 10, window, day(2)).unwrap();
    }

    #[tokio::test]
    async fn trait_methods_use_the_real_clock() {
        let quota = InMemoryQuota::default();
        quota.try_consume("k", 5, 10, WINDOW).await.unwrap();
        assert_eq!(quota.remaining("k", 10, WINDOW).await.unwrap(), 5);
    }
}
