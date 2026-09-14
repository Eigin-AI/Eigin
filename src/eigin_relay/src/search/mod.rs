//! Search-related modules: endpoint handler and client abstraction.

mod client;
mod focus;
mod handler;

pub use client::{
    SearchClient, SearchOptions, SearchResult, SearchResultItem, create_client, http_client,
};
pub use focus::SearchFocus;
pub use handler::handle;
