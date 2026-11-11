//! Cancellable HTTP bytes supplied by native networking or a host adapter.

mod callbacks;
#[cfg(not(target_arch = "wasm32"))]
mod default_transport;
mod operation;
mod types;

pub use callbacks::{HttpBodyChunkCallback, HttpResponseHeadCallback};
#[cfg(not(target_arch = "wasm32"))]
pub use default_transport::DefaultHttpTransport;
pub use operation::HttpOperation;
pub use types::*;
