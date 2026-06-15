//! Credit cost computation from upstream usage numbers.
//!
//! Rates are raw upstream cost anchored at 1 credit ≈ €0.01.
//! Margin and platform cut are applied in IAP tier pricing on the app side.

use crate::inference::catalog::ModelConfig;
use crate::inference::usage::UsageBlock;

/// Compute the cost in millicredits for a completed request.
///
/// Cost = (non-cached input × input rate + cached input × cached rate
///         + output × output rate) / 1,000,000
///
/// Rounded up to a minimum of 1 millicredit.
pub fn compute_cost(usage: &UsageBlock, model: &ModelConfig) -> i64 {
    let non_cached_input = usage.prompt_tokens.saturating_sub(usage.cached_tokens);
    let cached_input = usage.cached_tokens;
    let output = usage.completion_tokens;

    let cost = non_cached_input * model.input_millicredits_per_1m_tokens
        + cached_input * model.cached_input_millicredits_per_1m_tokens
        + output * model.output_millicredits_per_1m_tokens;

    // Divide by 1,000,000 (rates are per 1M tokens), round up, minimum 1.
    cost.div_ceil(1_000_000).max(1) as i64
}

#[cfg(test)]
mod tests {
    use super::*;

    fn model(input: u64, cached: u64, output: u64) -> ModelConfig {
        ModelConfig {
            id: "test-model".into(),
            input_millicredits_per_1m_tokens: input,
            cached_input_millicredits_per_1m_tokens: cached,
            output_millicredits_per_1m_tokens: output,
        }
    }

    fn usage(prompt: u64, cached: u64, completion: u64) -> UsageBlock {
        UsageBlock {
            prompt_tokens: prompt,
            completion_tokens: completion,
            cached_tokens: cached,
        }
    }

    #[test]
    fn basic_cost_no_cache() {
        // 1M input, 500k output at 10mc/1M and 20mc/1M
        let m = model(10, 0, 20);
        let u = usage(1_000_000, 0, 500_000);
        // cost = (1_000_000 * 10 + 0 + 500_000 * 20) / 1_000_000 = (10_000_000 + 10_000_000) / 1_000_000 = 20
        assert_eq!(compute_cost(&u, &m), 20);
    }

    #[test]
    fn cache_reduces_cost() {
        // 1M input (500k cached), 500k output at 10/1/20 mc/1M
        let m = model(10, 1, 20);
        let u = usage(1_000_000, 500_000, 500_000);
        // non-cached = 500_000, cached = 500_000
        // cost = (500_000*10 + 500_000*1 + 500_000*20) / 1_000_000
        //      = (5_000_000 + 500_000 + 10_000_000) / 1_000_000 = 15.5 → ceil = 16
        assert_eq!(compute_cost(&u, &m), 16);
    }

    #[test]
    fn minimum_cost_is_one_millicredit() {
        let m = model(0, 0, 0);
        let u = usage(1, 0, 1);
        assert_eq!(compute_cost(&u, &m), 1);
    }

    #[test]
    fn rounds_up_fractional_millicredits() {
        // 1 token at 1mc/1M → rounds up to 1
        let m = model(1, 0, 1);
        let u = usage(1, 0, 1);
        assert_eq!(compute_cost(&u, &m), 1);
    }
}
