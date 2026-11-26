//! Runtime coordination for one prepared inference request.
pub(crate) mod bindings;
pub use bindings::*;

mod cancellation;
mod driver;
mod events;
mod platform;
mod routed;
mod types;
mod work;

pub use cancellation::RequestCancellation;
pub use driver::{InferenceRequest, RequestReport};
pub use platform::RequestPlatform;
pub use routed::RoutedRequestEffects;
pub use types::*;

#[cfg(test)]
mod tests;
