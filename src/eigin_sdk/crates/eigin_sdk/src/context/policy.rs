use super::ContextPagingPolicy;

/// Reserves generation room and estimator headroom, then caps the paging trigger for long contexts.
#[uniffi::export]
pub fn default_paging_policy(context_window: i64, max_output: i64) -> ContextPagingPolicy {
    let reservation = max_output.clamp(0, 4096).min((context_window / 4).max(0));
    let available = context_window.saturating_sub(reservation).max(4);
    let maximum = ((i128::from(available) * 3 / 4) as i64).max(4);
    let trigger = ((i128::from(maximum) * 3 / 4) as i64).clamp(2, 250_000);
    ContextPagingPolicy {
        trigger_tokens: trigger,
        target_tokens: (trigger / 2).max(1),
        maximum_tokens: maximum,
        minimum_recent_turns: 2,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn budgets_leave_headroom_across_window_sizes() {
        for window in [16_000, 128_000, 250_000, 500_000, 1_000_000, i64::MAX] {
            let policy = default_paging_policy(window, window);
            assert!(policy.target_tokens > 0);
            assert!(policy.target_tokens < policy.trigger_tokens);
            assert!(policy.trigger_tokens <= policy.maximum_tokens);
            assert!(policy.maximum_tokens < window);
        }
    }

    #[test]
    fn malformed_limits_cannot_overflow() {
        for window in [i64::MIN, -1, 0, 1] {
            let policy = default_paging_policy(window, i64::MAX);
            assert!(policy.target_tokens > 0);
            assert!(policy.target_tokens < policy.trigger_tokens);
            assert!(policy.trigger_tokens <= policy.maximum_tokens);
        }
    }
}
