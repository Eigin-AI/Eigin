//! Model-asset mirror: serves versioned manifests + presigned download URLs
//! for the on-device model assets (Gemma, Plapre Pico, PocketTTS).
//!
//! Routes:
//! - GET /v1/assets        — list configured asset ids + current versions
//! - GET /v1/assets/{id}   — manifest for the pinned version + presigned GET urls

pub mod cache;
pub mod catalog;
pub mod handler;
pub mod store;

pub use cache::{AssetManifest, ManifestFile, ManifestOrigin};
pub use catalog::AssetsConfig;
pub use handler::{handle_get, handle_list};
pub use store::{AssetStore, ScalewayAssetStore};
