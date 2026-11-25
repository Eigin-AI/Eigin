//! Search evidence tiers and bounded memory adjustments.

// Explicit type-and-ID lookups take precedence over every other match.
pub(super) const QUALIFIED_ID_SCORE: f64 = 2.2;
// A short ID remains stronger evidence than a matching display name.
pub(super) const EXACT_ID_SCORE: f64 = 2.0;
// A complete name or title outranks a phrase within a longer identity.
pub(super) const EXACT_NAME_SCORE: f64 = 1.8;
// A phrase in an ID, name, or title outweighs matches across body fields.
pub(super) const IDENTITY_PHRASE_SCORE: f64 = 1.6;
// Covering every query word outranks prefix-only and partial matches.
pub(super) const FULL_COVERAGE_SCORE: f64 = 1.2;
// Prefix coverage provides weaker evidence than complete query words.
pub(super) const PREFIX_COVERAGE_SCORE: f64 = 0.6;
// Partial matches scale this ceiling by the fraction of query words found.
pub(super) const PARTIAL_COVERAGE_SCORE: f64 = 0.4;
// Short fragments are too ambiguous to count as prefix evidence.
pub(super) const MIN_PREFIX_GRAPHEMES: usize = 4;

// Bound historical use before decay so heavily used memories can still fade.
pub(super) const ACCESS_COUNT_CAP: f64 = 16.0;
// Halve the effective access count after this many days without an access.
pub(super) const ACCESS_HALF_LIFE_DAYS: f64 = 14.0;
// An effective access count at this value yields activation 0.5.
pub(super) const ACCESS_SATURATION: f64 = 4.0;
// This importance produces no lift or penalty.
pub(super) const NEUTRAL_IMPORTANCE: f64 = 0.5;
// Map importance above neutral to a stronger positive contribution.
pub(super) const IMPORTANCE_RISE_MULTIPLIER: f64 = 2.0;
// Penalize low importance more gently than high importance is rewarded.
pub(super) const IMPORTANCE_FALL_MULTIPLIER: f64 = 0.5;

// Keep memory signals small relative to query evidence.
pub(super) const MEMORY_ADJUSTMENT_BUDGET: f64 = 0.05;
// Allocate this share of the memory adjustment to decayed access history.
pub(super) const ACCESS_WEIGHT: f64 = 0.3;
// Allocate this share to host-assigned importance.
pub(super) const IMPORTANCE_WEIGHT: f64 = 0.35;
// Normalize the access and importance shares to the memory budget.
pub(super) const MEMORY_WEIGHT_TOTAL: f64 = 0.65;
// Keep opposing adjustments from reversing adjacent relevance tiers.
pub(super) const MAX_TIER_ADJUSTMENT: f64 = 0.09;
