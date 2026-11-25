use std::{
    collections::{HashMap, HashSet},
    sync::Arc,
};

use firm_core::{
    EntitySchema, EntityType, compose_entity_id,
    graph::{EntityGraph, Query, QueryResult},
};
use firm_lang::{
    parser::{dsl::parse_source, query::parse_query},
    workspace::Workspace,
};

use super::{paths, types::*};

/// An experimental immutable graph built only from host-authorized source contents.
/// Hosts retain the committed instance until durable changes have been saved.
#[derive(uniffi::Object)]
pub struct KnowledgeWorkspace {
    sources: Vec<KnowledgeSource>,
    entity_sources: HashMap<String, usize>,
    schemas: Vec<EntitySchema>,
    graph: EntityGraph,
}

#[uniffi::export]
impl KnowledgeWorkspace {
    /// Builds and validates an authorized source snapshot without filesystem access.
    #[uniffi::constructor]
    pub fn new(mut sources: Vec<KnowledgeSource>) -> Result<Self, KnowledgeError> {
        let mut workspace = Workspace::new();
        let mut ids = HashSet::new();
        let mut paths = HashSet::new();
        let mut entity_sources = HashMap::new();
        for (index, source) in sources.iter_mut().enumerate() {
            if source.id.is_empty() {
                return Err(KnowledgeError::EmptySourceId);
            }
            if !ids.insert(source.id.clone()) {
                return Err(KnowledgeError::DuplicateSource {
                    value: source.id.clone(),
                });
            }
            source.path = paths::normalize(&source.path)?;
            if !paths.insert(source.path.clone()) {
                return Err(KnowledgeError::DuplicateSource {
                    value: source.path.clone(),
                });
            }
            let parsed = parse_source(source.content.clone(), Some(source.path.clone().into()))
                .map_err(|error| KnowledgeError::Parse {
                    source_id: source.id.clone(),
                    message: error.to_string(),
                })?;
            for entity in parsed.entities() {
                if let (Some(entity_type), Some(id)) = (entity.entity_type(), entity.id()) {
                    entity_sources.insert(compose_entity_id(entity_type, id).to_string(), index);
                }
            }
            workspace.add_parsed_source(parsed);
        }
        let built = workspace.build().map_err(|error| KnowledgeError::Build {
            message: error.to_string(),
        })?;
        let mut graph = EntityGraph::new();
        graph
            .add_entities(built.entities)
            .map_err(|error| KnowledgeError::Build {
                message: format!("{error:?}"),
            })?;
        graph.build();
        Ok(Self {
            sources,
            entity_sources,
            schemas: built.schemas,
            graph,
        })
    }

    /// Returns supplied source identities and contents, with normalized logical paths.
    pub fn sources(&self) -> Vec<KnowledgeSource> {
        self.sources.clone()
    }

    /// Executes a Firm query, preserving aggregate display strings.
    pub fn query(&self, query_string: String) -> Result<KnowledgeQueryResult, KnowledgeError> {
        let parsed = parse_query(&query_string).map_err(|error| KnowledgeError::Query {
            message: error.to_string(),
        })?;
        let query = Query::try_from(parsed).map_err(|error| KnowledgeError::Query {
            message: error.to_string(),
        })?;
        match query
            .execute(&self.graph)
            .map_err(|error| KnowledgeError::Query {
                message: error.to_string(),
            })? {
            QueryResult::Entities(entities) => Ok(KnowledgeQueryResult::Entities {
                entities: entities.into_iter().map(KnowledgeEntity::from).collect(),
            }),
            QueryResult::Aggregation(value) => Ok(KnowledgeQueryResult::Aggregation {
                value: value.to_string(),
            }),
        }
    }

    /// Finds an entity using its type and short ID.
    pub fn get_entity(&self, entity_type: String, id: String) -> Option<KnowledgeEntity> {
        self.graph
            .get_entity(&compose_entity_id(&entity_type, &id))
            .map(KnowledgeEntity::from)
    }

    /// Lists qualified entity IDs for a type in deterministic order.
    pub fn list_entities(&self, entity_type: String) -> Vec<String> {
        let mut ids: Vec<_> = self
            .graph
            .list_by_type(&EntityType::new(&entity_type))
            .iter()
            .map(|entity| entity.id.to_string())
            .collect();
        ids.sort();
        ids
    }

    /// Lists schema names in deterministic order.
    pub fn list_schemas(&self) -> Vec<String> {
        let mut names: Vec<_> = self
            .schemas
            .iter()
            .map(|schema| schema.entity_type.to_string())
            .collect();
        names.sort();
        names
    }

    /// Returns ordered fields and constraints for a schema.
    pub fn get_schema(&self, entity_type: String) -> Option<KnowledgeSchema> {
        self.schemas
            .iter()
            .find(|schema| schema.entity_type == EntityType::new(&entity_type))
            .map(|schema| KnowledgeSchema {
                entity_type: schema.entity_type.to_string(),
                fields: schema
                    .ordered_fields()
                    .iter()
                    .map(|(id, field)| KnowledgeSchemaField {
                        name: id.to_string(),
                        field_type: field.expected_type().to_string(),
                        required: field.is_required(),
                        allowed_values: field.allowed_values().cloned(),
                    })
                    .collect(),
            })
    }

    /// Traverses relationships without loading additional sources.
    pub fn get_related(
        &self,
        entity_type: String,
        id: String,
        direction: KnowledgeDirection,
    ) -> Vec<KnowledgeEntity> {
        let direction = match direction {
            KnowledgeDirection::Incoming => Some(firm_core::graph::Direction::Incoming),
            KnowledgeDirection::Outgoing => Some(firm_core::graph::Direction::Outgoing),
            KnowledgeDirection::Both => None,
        };
        self.graph
            .get_related(&compose_entity_id(&entity_type, &id), direction)
            .unwrap_or_default()
            .into_iter()
            .map(KnowledgeEntity::from)
            .collect()
    }

    /// Returns the stable host source identity for an entity.
    pub fn find_entity_source(&self, entity_type: String, id: String) -> Option<KnowledgeSource> {
        self.entity_sources
            .get(&compose_entity_id(&entity_type, &id).to_string())
            .map(|index| self.sources[*index].clone())
    }

    /// Generates and verifies source-relative DSL at Firm's supported precision.
    pub fn generate_entity_dsl(
        &self,
        entity: KnowledgeEntity,
        source_path: String,
    ) -> Result<String, KnowledgeError> {
        super::serialization::generate(entity, source_path)
    }

    /// Validates a source replacement or insertion without changing this snapshot.
    pub fn replacing_source(&self, source: KnowledgeSource) -> Result<Arc<Self>, KnowledgeError> {
        let mut sources = self.sources.clone();
        if let Some(existing) = sources.iter_mut().find(|item| item.id == source.id) {
            if existing.read_only {
                return Err(KnowledgeError::ProtectedSource {
                    source_id: source.id,
                });
            }
            *existing = source;
        } else {
            sources.push(source);
        }
        Self::new(sources).map(Arc::new)
    }

    /// Validates source removal without changing this snapshot.
    pub fn removing_source(&self, source_id: String) -> Result<Arc<Self>, KnowledgeError> {
        let source = self
            .sources
            .iter()
            .find(|source| source.id == source_id)
            .ok_or_else(|| KnowledgeError::MissingSource {
                source_id: source_id.clone(),
            })?;
        if source.read_only {
            return Err(KnowledgeError::ProtectedSource { source_id });
        }
        Self::new(
            self.sources
                .iter()
                .filter(|source| source.id != source_id)
                .cloned()
                .collect(),
        )
        .map(Arc::new)
    }
}
