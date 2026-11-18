//! Transient agent round handling; execution and orchestration belong to the host.
mod arguments;
mod round;
mod types;

pub use round::AgentRound;
pub use types::*;

#[cfg(test)]
mod tests;
