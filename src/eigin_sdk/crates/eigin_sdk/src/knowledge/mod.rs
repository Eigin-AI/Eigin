//! Experimental source-backed knowledge. Hosts own authorization and durable storage.

mod conversion;
mod embedding;
mod lexical;
mod paths;
mod policy;
mod ranking;
mod scope;
mod serialization;
mod types;
mod workspace;

pub use embedding::knowledge_embedding_text;
pub use lexical::knowledge_lexical_score;
pub use ranking::*;
pub use scope::*;
pub use types::*;
pub use workspace::KnowledgeWorkspace;

#[cfg(test)]
mod tests;
