//! Monotonic execution deadlines shared by tools and inference attempts.
#[cfg(not(target_vendor = "apple"))]
use std::time::Duration;

#[cfg(target_vendor = "apple")]
mod apple;
#[cfg(target_vendor = "apple")]
pub(crate) use apple::{now, sleep_until};

#[cfg(not(target_vendor = "apple"))]
pub(crate) fn now() -> Duration {
    static ORIGIN: std::sync::OnceLock<web_time::Instant> = std::sync::OnceLock::new();
    ORIGIN.get_or_init(web_time::Instant::now).elapsed()
}

#[cfg(not(target_vendor = "apple"))]
pub(crate) async fn sleep_until(deadline: Duration) {
    let remaining = deadline.saturating_sub(now());
    #[cfg(not(target_arch = "wasm32"))]
    futures_timer::Delay::new(remaining).await;
    #[cfg(target_arch = "wasm32")]
    gloo_timers::future::TimeoutFuture::new(
        remaining
            .as_nanos()
            .div_ceil(1_000_000)
            .min(i32::MAX as u128) as u32,
    )
    .await;
}
