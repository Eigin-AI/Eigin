//! Embedded model metadata, ID matching, preferences, and reasoning/context policy.
//! The TOML manifest orders model files; the first matching pattern or alias wins.
//! Record and ranking order are independent. All assets are compiled into the SDK.
mod catalog;
mod config;
mod matching;
mod policy;
mod types;

pub use catalog::ModelCatalog;
pub use types::*;

#[cfg(test)]
mod tests;
