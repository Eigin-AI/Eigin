//! Value-based context sizing and history selection.

mod estimate;
mod paging;
mod policy;
mod request;
mod selection;
mod summary;

pub use estimate::{
    ContextMessage, ContextToolCall, estimate_messages, estimate_request, estimate_text,
    estimate_tools,
};
pub use paging::{
    ContextPageSelection, ContextPagingError, ContextPagingInput, ContextPagingPolicy,
    ContextPagingResult, ContextProtectedRange, OMITTED_TOOL_RESULT, page_context,
};
pub use policy::default_paging_policy;
pub use request::{estimate_request_with_tools, estimate_serialized_tools};
pub use selection::{ContextSelection, retained_tail, truncate_for_budget, windowed_for_budget};
pub use summary::{SummaryParseResult, parse_summary};

#[cfg(test)]
mod tests;
