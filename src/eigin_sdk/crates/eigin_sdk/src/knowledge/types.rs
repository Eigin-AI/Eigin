// Adapted from 42futures/firm PR #53 (ecd9d9a), licensed AGPL-3.0.
//! UniFFI-compatible types that mirror firm_core's domain types.
//!
//! These are thin wrappers that avoid exposing Rust-specific types
//! (Decimal, Currency, DateTime, PathBuf) across the FFI boundary.

/// A Knowledge entity with its type, ID, and fields.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct KnowledgeEntity {
    /// Composite ID (e.g. "person.alice").
    pub id: String,
    /// Entity type (e.g. "person").
    pub entity_type: String,
    /// Ordered list of fields.
    pub fields: Vec<KnowledgeField>,
}

/// A named field on an entity.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct KnowledgeField {
    pub name: String,
    pub value: KnowledgeFieldValue,
}

/// The value of an entity field.
///
/// Mirrors firm_core's `FieldValue` with FFI-safe types.
/// `ReferenceValue` is flattened into two variants.
/// `Currency` and `DateTime` use string representations.
#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum KnowledgeFieldValue {
    Boolean {
        value: bool,
    },
    String {
        value: String,
    },
    Integer {
        value: i64,
    },
    Float {
        value: f64,
    },
    /// Currency as decimal string + ISO 4217 code (e.g. "123.45", "USD").
    Currency {
        amount: String,
        currency_code: String,
    },
    /// Reference to another entity (e.g. "person.alice").
    EntityReference {
        entity_id: String,
    },
    /// Reference to a field on another entity.
    FieldReference {
        entity_id: String,
        field_id: String,
    },
    /// Ordered list of values.
    List {
        items: Vec<KnowledgeFieldValue>,
    },
    /// ISO 8601 / RFC 3339 datetime string.
    DateTime {
        value: String,
    },
    /// File path as string.
    Path {
        value: String,
    },
    /// Enum variant name.
    Enum {
        value: String,
    },
}

/// Direction for traversing entity relationships.
#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum KnowledgeDirection {
    /// Entities this entity references.
    Outgoing,
    /// Entities that reference this entity.
    Incoming,
    /// Both directions.
    Both,
}

/// The result of executing a query.
#[derive(Debug, Clone, PartialEq, uniffi::Enum)]
pub enum KnowledgeQueryResult {
    /// Matching entities.
    Entities { entities: Vec<KnowledgeEntity> },
    /// Aggregation result as a display string (count, sum, average, etc.).
    Aggregation { value: String },
}

/// A schema definition for an entity type.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct KnowledgeSchema {
    /// Entity type name (e.g. "actor").
    pub entity_type: String,
    /// Fields in schema order.
    pub fields: Vec<KnowledgeSchemaField>,
}

/// A field definition within an entity schema.
#[derive(Debug, Clone, PartialEq, uniffi::Record)]
pub struct KnowledgeSchemaField {
    /// Field name (e.g. "name").
    pub name: String,
    /// Field type (e.g. "String", "Enum", "List").
    pub field_type: String,
    /// Whether the field is required.
    pub required: bool,
    /// Allowed values for enum fields, if constrained.
    pub allowed_values: Option<Vec<String>>,
}

/// An authorized source supplied by the host; IDs remain stable across content edits.
#[derive(Debug, Clone, PartialEq, Eq, uniffi::Record)]
pub struct KnowledgeSource {
    pub id: String,
    pub path: String,
    pub content: String,
    pub read_only: bool,
}

/// Failures while constructing, querying, or preparing a knowledge workspace.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error, uniffi::Error)]
pub enum KnowledgeError {
    #[error("Invalid logical source path: {path}")]
    InvalidPath { path: String },
    #[error("Duplicate source path or identity: {value}")]
    DuplicateSource { value: String },
    #[error("Source identity must not be empty")]
    EmptySourceId,
    #[error("Source {source_id} failed to parse: {message}")]
    Parse { source_id: String, message: String },
    #[error("Workspace validation failed: {message}")]
    Build { message: String },
    #[error("Query failed: {message}")]
    Query { message: String },
    #[error("Invalid entity: {message}")]
    InvalidEntity { message: String },
    #[error("Source is protected: {source_id}")]
    ProtectedSource { source_id: String },
    #[error("Source does not exist: {source_id}")]
    MissingSource { source_id: String },
}
