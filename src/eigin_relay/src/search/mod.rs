//! Search-related modules: endpoint handler and client abstraction.

mod client;
mod handler;

pub use client::{SearchClient, SearchFocus, SearchOptions, create_client};
pub use handler::handle;
