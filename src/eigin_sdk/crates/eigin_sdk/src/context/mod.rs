//! Value-based context sizing and history selection.

mod estimate;
mod selection;
mod summary;

pub use estimate::{
    ContextMessage, ContextToolCall, estimate_messages, estimate_request, estimate_text,
    estimate_tools,
};
pub use selection::{ContextSelection, retained_tail, truncate_for_budget, windowed_for_budget};
pub use summary::{SummaryParseResult, parse_summary};
