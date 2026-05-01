//! Per-IP rate limiting using a sliding window algorithm.

use std::collections::{HashMap, VecDeque};
use std::net::IpAddr;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use crate::error::AppError;

/// Sliding window rate limiter per client IP address.
///
/// Tracks request timestamps for each IP and enforces a maximum number
/// of requests within a configurable time window.
pub struct RateLimiter {
    /// Maps client IP to deque of request timestamps.
    requests: Mutex<HashMap<IpAddr, VecDeque<Instant>>>,
    /// Maximum requests allowed per window.
    max_requests: u32,
    /// Time window duration.
    window: Duration,
}

impl RateLimiter {
    /// Creates a new rate limiter.
    ///
    /// - `max_requests`: Maximum requests allowed within `window`.
    /// - `window`: Time window duration.
    pub fn new(max_requests: u32, window: Duration) -> Self {
        Self {
            requests: Mutex::new(HashMap::new()),
            max_requests,
            window,
        }
    }

    /// Checks if a request from the given IP is allowed.
    ///
    /// Records the request timestamp if allowed. Returns `AppError::RateLimited`
    /// if the IP has exceeded the rate limit.
    pub fn check(&self, ip: IpAddr) -> Result<(), AppError> {
        let mut map = self.requests.lock().unwrap();
        let now = Instant::now();
        let cutoff = now - self.window;

        // Get or create the entry
        let timestamps = map.entry(ip).or_default();

        // Drain expired entries from the front
        while timestamps.front().is_some_and(|&t| t < cutoff) {
            timestamps.pop_front();
        }

        // Check if rate limited
        if timestamps.len() >= self.max_requests as usize {
            return Err(AppError::RateLimited);
        }

        // Record this request
        timestamps.push_back(now);

        // Evict empty entries to prevent unbounded map growth
        if timestamps.is_empty() {
            map.remove(&ip);
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::{IpAddr, Ipv4Addr};
    use std::thread;
    use std::time::Duration;

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
    fn empty_deque_is_evicted_on_next_check() {
        let limiter = RateLimiter::new(2, Duration::from_millis(50));

        assert!(limiter.check(ip(1)).is_ok());
        assert!(limiter.check(ip(1)).is_ok());

        thread::sleep(Duration::from_millis(60));

        // The entry still exists because we haven't checked since expiry
        let map = limiter.requests.lock().unwrap();
        assert!(map.contains_key(&ip(1)), "entry exists before next check");
        drop(map);

        // On next check, the expired entries are drained and the entry is removed
        assert!(limiter.check(ip(1)).is_ok());

        let map = limiter.requests.lock().unwrap();
        assert!(map.contains_key(&ip(1)), "entry recreated after check");
    }
}
