use std::time::Duration;

/// Wall-clock instant expressed as fractional, signed Unix seconds.
#[derive(Clone, Copy, Default, PartialEq, PartialOrd)]
pub(crate) struct WallTime(f64);

impl WallTime {
    pub fn from_unix_seconds(seconds: f64) -> Self {
        Self(seconds)
    }

    pub fn unix_seconds(self) -> f64 {
        self.0
    }

    pub fn seconds_since(self, earlier: Self) -> f64 {
        self.0 - earlier.0
    }

    pub fn after(self, duration: Duration) -> Self {
        Self(self.0 + duration.as_secs_f64())
    }
}
