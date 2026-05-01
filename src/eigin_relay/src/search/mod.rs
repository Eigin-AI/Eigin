//! Search-related modules: endpoint handler, client abstraction, and quota pool.

mod client;
mod handler;
mod pool;

pub use client::{SearchClient, create_client};
pub use handler::handle;
pub use pool::Pool;
