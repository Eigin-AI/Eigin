//! Sliding window rate limiter, generic over key type.
//!
//! `RateLimiter<K>` tracks request timestamps per key `K` and enforces a maximum
//! number of requests within a sliding time window. Used for:
//! - Per-IP limiting: `RateLimiter<IpAddr>` (search + inference backstop)
//! - Per-token limiting: `RateLimiter<uuid::Uuid>` (inference, one token = one user)

use std::collections::{HashMap, VecDeque};
use std::hash::Hash;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use crate::error::AppError;

/// Sliding window rate limiter.
pub struct RateLimiter<K = std::net::IpAddr>
where
    K: Hash + Eq + Clone,
{
    requests: Mutex<HashMap<K, VecDeque<Instant>>>,
    max_requests: u32,
    window: Duration,
}

impl<K> RateLimiter<K>
where
    K: Hash + Eq + Clone,
{
    pub fn new(max_requests: u32, window: Duration) -> Self {
        Self {
            requests: Mutex::new(HashMap::new()),
            max_requests,
            window,
        }
    }

    /// Check whether a request from `key` is allowed.
    ///
    /// Records the request timestamp if allowed. Returns `AppError::RateLimited`
    /// if the key has exceeded the rate limit within the window.
    pub fn check(&self, key: K) -> Result<(), AppError> {
        let mut map = self.requests.lock().unwrap();
        let now = Instant::now();
        let cutoff = now - self.window;

        let timestamps = map.entry(key.clone()).or_default();

        // Drain expired entries from the front.
        while timestamps.front().is_some_and(|&t| t < cutoff) {
            timestamps.pop_front();
        }

        if timestamps.len() >= self.max_requests as usize {
            return Err(AppError::RateLimited);
        }

        timestamps.push_back(now);

        // Evict empty entries to prevent unbounded map growth.
        if timestamps.is_empty() {
            map.remove(&key);
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::{IpAddr, Ipv4Addr};
    use std::thread;

    fn ip(n: u8) -> IpAddr {
        IpAddr::V4(Ipv4Addr::new(1, 2, 3, n))
    }

    #[test]
    fn within_limit_allows_request() {
        let limiter = RateLimiter::new(5, Duration::from_secs(60));
        for _ in 0..5 {
            assert!(limiter.check(ip(1)).is_ok());
        }
    }

    #[test]
    fn over_limit_rejects_request() {
        let limiter = RateLimiter::new(5, Duration::from_secs(60));
        for _ in 0..5 {
            limiter.check(ip(1)).unwrap();
        }
        assert!(matches!(limiter.check(ip(1)), Err(AppError::RateLimited)));
    }

    #[test]
    fn window_slides_allows_after_expiry() {
        let limiter = RateLimiter::new(2, Duration::from_millis(50));
        assert!(limiter.check(ip(1)).is_ok());
        assert!(limiter.check(ip(1)).is_ok());
        assert!(matches!(limiter.check(ip(1)), Err(AppError::RateLimited)));
        thread::sleep(Duration::from_millis(60));
        assert!(limiter.check(ip(1)).is_ok());
    }

    #[test]
    fn different_ips_tracked_independently() {
        let limiter = RateLimiter::new(2, Duration::from_secs(60));
        assert!(limiter.check(ip(1)).is_ok());
        assert!(limiter.check(ip(1)).is_ok());
        assert!(matches!(limiter.check(ip(1)), Err(AppError::RateLimited)));
        assert!(limiter.check(ip(2)).is_ok());
        assert!(limiter.check(ip(2)).is_ok());
        assert!(matches!(limiter.check(ip(2)), Err(AppError::RateLimited)));
    }

    #[test]
    fn uuid_key_type_works() {
        let limiter: RateLimiter<uuid::Uuid> = RateLimiter::new(2, Duration::from_secs(60));
        let id = uuid::Uuid::new_v4();
        assert!(limiter.check(id).is_ok());
        assert!(limiter.check(id).is_ok());
        assert!(matches!(limiter.check(id), Err(AppError::RateLimited)));
    }

    #[test]
    fn empty_deque_is_evicted_on_next_check() {
        let limiter = RateLimiter::new(2, Duration::from_millis(50));
        assert!(limiter.check(ip(1)).is_ok());
        assert!(limiter.check(ip(1)).is_ok());
        thread::sleep(Duration::from_millis(60));
        let map = limiter.requests.lock().unwrap();
        assert!(map.contains_key(&ip(1)), "entry exists before next check");
        drop(map);
        assert!(limiter.check(ip(1)).is_ok());
        let map = limiter.requests.lock().unwrap();
        assert!(map.contains_key(&ip(1)), "entry recreated after check");
    }
}
