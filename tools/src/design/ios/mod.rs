//! iOS design codegen. Orchestration lives in `design::generate_all` so the
//! tokens load and font discovery run once for all platforms.

pub mod assets;
pub mod fonts;
pub mod icons;
pub mod launch;
mod model;
pub mod style;
mod swift_mappings;
