use super::{
    KnowledgeEntity,
    lexical::{LexicalQuery, short_id},
    policy::*,
};

/// Host memory metadata for an authorized entity; timestamps are Unix seconds.
#[derive(Clone, Debug, uniffi::Record)]
pub struct KnowledgeMemory {
    pub source_id: String,
    pub embedding: Vec<f64>,
    pub access_count: f64,
    pub last_accessed_at: Option<f64>,
    pub importance: f64,
    pub expired: bool,
    pub chat_id: Option<String>,
}

/// An authorized graph entity and its optional persisted memory signals.
#[derive(Clone, Debug, uniffi::Record)]
pub struct KnowledgeSearchCandidate {
    pub entity: KnowledgeEntity,
    pub memory: Option<KnowledgeMemory>,
}

/// Relevance controls inclusion; score controls ordering within relevance tiers.
#[derive(Clone, Debug, uniffi::Record)]
pub struct KnowledgeSearchResult {
    pub entity: KnowledgeEntity,
    pub qualified_id: String,
    pub source_id: Option<String>,
    pub chat_id: Option<String>,
    pub relevance: f64,
    pub score: f64,
}

/// Measures vector similarity; incompatible or zero-length vectors have no evidence.
#[uniffi::export]
pub fn knowledge_cosine_similarity(lhs: Vec<f64>, rhs: Vec<f64>) -> f64 {
    cosine(&lhs, &rhs)
}

fn cosine(lhs: &[f64], rhs: &[f64]) -> f64 {
    if lhs.is_empty() || lhs.len() != rhs.len() {
        return 0.0;
    }
    let dot: f64 = lhs.iter().zip(rhs).map(|(a, b)| a * b).sum();
    let norm_a = lhs.iter().map(|v| v * v).sum::<f64>().sqrt();
    let norm_b = rhs.iter().map(|v| v * v).sum::<f64>().sqrt();
    if norm_a == 0.0 || norm_b == 0.0 {
        return 0.0;
    }
    dot / (norm_a * norm_b)
}

/// Computes recency-decayed access activation, capped before decay.
#[uniffi::export]
pub fn knowledge_memory_activation(
    access_count: f64,
    last_accessed_at: Option<f64>,
    now: f64,
) -> f64 {
    let Some(last) = last_accessed_at.filter(|_| access_count > 0.0) else {
        return 0.0;
    };
    let elapsed_days = (now - last).max(0.0) / 86400.0;
    let effective = access_count.min(ACCESS_COUNT_CAP)
        * (-elapsed_days / ACCESS_HALF_LIFE_DAYS * 2.0_f64.ln()).exp();
    effective / (effective + ACCESS_SATURATION)
}

/// Computes the asymmetric importance contribution around neutral importance 0.5.
#[uniffi::export]
pub fn knowledge_importance_lift(importance: f64) -> f64 {
    let delta = importance - NEUTRAL_IMPORTANCE;
    if delta >= 0.0 {
        delta * IMPORTANCE_RISE_MULTIPLIER
    } else {
        delta * IMPORTANCE_FALL_MULTIPLIER
    }
}

/// Computes a small query-independent memory adjustment.
#[uniffi::export]
pub fn knowledge_memory_boost(
    access_count: f64,
    last_accessed_at: Option<f64>,
    importance: f64,
    now: f64,
) -> f64 {
    (MEMORY_ADJUSTMENT_BUDGET * ACCESS_WEIGHT / MEMORY_WEIGHT_TOTAL)
        * knowledge_memory_activation(access_count, last_accessed_at, now)
        + (MEMORY_ADJUSTMENT_BUDGET * IMPORTANCE_WEIGHT / MEMORY_WEIGHT_TOTAL)
            * knowledge_importance_lift(importance.clamp(0.0, 1.0))
}

/// Bounds memory adjustments within protected relevance bands.
#[uniffi::export]
pub fn knowledge_ranking_score(relevance: f64, adjustment: f64) -> f64 {
    relevance + (adjustment * relevance.min(1.0)).clamp(-MAX_TIER_ADJUSTMENT, MAX_TIER_ADJUSTMENT)
}

/// Scores supplied candidates in input order; host embedding generation remains external.
#[uniffi::export]
pub fn knowledge_score_candidates(
    candidates: Vec<KnowledgeSearchCandidate>,
    query_embedding: Vec<f64>,
    keyword_needle: Option<String>,
    include_expired: bool,
    now: f64,
) -> Vec<KnowledgeSearchResult> {
    let query = LexicalQuery::new(keyword_needle.as_deref().unwrap_or(""));
    candidates
        .into_iter()
        .filter_map(|candidate| {
            let KnowledgeSearchCandidate { entity, memory } = candidate;
            if !include_expired && memory.as_ref().is_some_and(|memory| memory.expired) {
                return None;
            }
            let qualified_id = format!("{}.{}", entity.entity_type, short_id(&entity));
            let semantic = memory
                .as_ref()
                .map_or(0.0, |memory| cosine(&query_embedding, &memory.embedding));
            let relevance = semantic.max(query.score(&entity, &qualified_id));
            if relevance <= 0.0 {
                return None;
            }
            let boost = memory.as_ref().map_or(0.0, |memory| {
                knowledge_memory_boost(
                    memory.access_count,
                    memory.last_accessed_at,
                    memory.importance,
                    now,
                )
            });
            Some(KnowledgeSearchResult {
                entity,
                qualified_id,
                relevance,
                score: knowledge_ranking_score(relevance, boost),
                source_id: memory.as_ref().map(|memory| memory.source_id.clone()),
                chat_id: memory.and_then(|memory| memory.chat_id),
            })
        })
        .collect()
}

/// Filters by relevance, then ranks with deterministic qualified-ID tie-breaking.
#[uniffi::export]
pub fn knowledge_rank_results(
    mut results: Vec<KnowledgeSearchResult>,
    threshold: f64,
    limit: Option<u64>,
) -> Vec<KnowledgeSearchResult> {
    if threshold > 0.0 {
        results.retain(|result| result.relevance >= threshold);
    }
    results.sort_by(|a, b| {
        b.score
            .total_cmp(&a.score)
            .then_with(|| a.qualified_id.cmp(&b.qualified_id))
    });
    if let Some(limit) = limit {
        results.truncate(usize::try_from(limit).unwrap_or(usize::MAX));
    }
    results
}
