//! Shared day-bucket math for the quota implementations.

use std::time::Duration;

use time::{Date, OffsetDateTime};

/// The UTC day of `now` and the earliest day still inside the trailing `window`.
///
/// Buckets are whole UTC days, so the window is rounded up to a whole number of
/// days (at least one). For a 30-day window this returns `today` and `today - 29`,
/// i.e. the 30 days ending today. Aging is therefore quantized to day boundaries.
pub fn window_bounds(window: Duration, now: OffsetDateTime) -> (Date, Date) {
    let today = now.date();
    let days = window.as_secs().div_ceil(24 * 60 * 60).max(1);
    // Saturating guards against absurdly large windows running off the calendar.
    let cutoff = today.saturating_sub(time::Duration::days((days - 1) as i64));
    (today, cutoff)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn at(year: i32, month: time::Month, day: u8) -> OffsetDateTime {
        Date::from_calendar_date(year, month, day)
            .unwrap()
            .midnight()
            .assume_utc()
    }

    #[test]
    fn thirty_day_window_spans_thirty_days_ending_today() {
        let now = at(2026, time::Month::June, 30);
        let (today, cutoff) = window_bounds(Duration::from_secs(30 * 24 * 60 * 60), now);
        assert_eq!(today, at(2026, time::Month::June, 30).date());
        assert_eq!(cutoff, at(2026, time::Month::June, 1).date());
    }

    #[test]
    fn sub_day_window_is_at_least_today() {
        let now = at(2026, time::Month::June, 30);
        let (today, cutoff) = window_bounds(Duration::from_secs(60), now);
        assert_eq!(cutoff, today);
    }
}
