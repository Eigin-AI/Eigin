use std::time::Duration;

#[cfg(not(target_arch = "wasm32"))]
pub(crate) type ClockSleep = futures_util::future::BoxFuture<'static, ()>;
#[cfg(target_arch = "wasm32")]
pub(crate) type ClockSleep = futures_util::future::LocalBoxFuture<'static, ()>;

/// Request-scoped monotonic time and deadline waiting from the same source.
pub(crate) trait ExecutionClock: Send + Sync {
    fn now(&self) -> Duration;
    fn sleep_until(&self, deadline: Duration) -> ClockSleep;
}

/// Monotonic time and timers supplied by the current platform.
pub(crate) struct PlatformClock;

impl ExecutionClock for PlatformClock {
    fn now(&self) -> Duration {
        super::now()
    }

    fn sleep_until(&self, deadline: Duration) -> ClockSleep {
        Box::pin(super::sleep_until(deadline))
    }
}
