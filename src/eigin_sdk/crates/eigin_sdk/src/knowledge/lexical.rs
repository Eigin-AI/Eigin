use std::collections::HashSet;

use firm_core::EntityId;
use icu_normalizer::ComposingNormalizer;
use unicode_segmentation::UnicodeSegmentation;

use super::{KnowledgeEntity, KnowledgeFieldValue, policy::*};

fn canonical(value: &str) -> String {
    ComposingNormalizer::new_nfc().normalize(value).into_owned()
}

fn words(text: &str) -> Vec<String> {
    let text = canonical(&text.to_lowercase());
    let mut result = Vec::new();
    let mut word = String::new();
    for character in text.graphemes(true) {
        if character
            .chars()
            .next()
            .is_some_and(|value| value.is_alphabetic() || value.is_numeric())
        {
            word.push_str(character);
        } else if !word.is_empty() {
            result.push(std::mem::take(&mut word));
        }
    }
    if !word.is_empty() {
        result.push(word);
    }
    result
}

fn phrase(words: &[String], query: &[String]) -> bool {
    !query.is_empty() && words.windows(query.len()).any(|window| window == query)
}

pub(super) fn short_id(entity: &KnowledgeEntity) -> &str {
    entity
        .id
        .strip_prefix(&format!("{}.", entity.entity_type))
        .unwrap_or(&entity.id)
}

fn text_values<'a>(value: &'a KnowledgeFieldValue, values: &mut Vec<&'a str>) {
    match value {
        KnowledgeFieldValue::String { value } | KnowledgeFieldValue::Enum { value } => {
            values.push(value)
        }
        KnowledgeFieldValue::EntityReference { entity_id } => values.push(entity_id),
        KnowledgeFieldValue::List { items } => {
            for value in items {
                text_values(value, values);
            }
        }
        _ => {}
    }
}

pub(super) struct LexicalQuery {
    tokens: Vec<String>,
    normalized_id: String,
}

impl LexicalQuery {
    pub fn new(text: &str) -> Self {
        Self {
            tokens: words(text),
            normalized_id: canonical(&EntityId::new(text.trim()).to_string()),
        }
    }

    pub fn score(&self, entity: &KnowledgeEntity, qualified_id: &str) -> f64 {
        let tokens = &self.tokens;
        if tokens.is_empty() {
            return 0.0;
        }
        if self.normalized_id == canonical(&EntityId::new(qualified_id).to_string()) {
            return QUALIFIED_ID_SCORE;
        }
        let short = short_id(entity);
        if self.normalized_id == canonical(&EntityId::new(short).to_string()) {
            return EXACT_ID_SCORE;
        }
        let short_tokens = words(short);
        let mut identity_phrase = phrase(&short_tokens, tokens);
        let mut all_tokens: HashSet<String> = short_tokens.into_iter().collect();
        for field in &entity.fields {
            let mut values = Vec::new();
            text_values(&field.value, &mut values);
            for value in values {
                let words = words(value);
                if field.name == "name" || field.name == "title" {
                    if words == *tokens {
                        return EXACT_NAME_SCORE;
                    }
                    identity_phrase |= phrase(&words, tokens);
                }
                all_tokens.extend(words);
            }
        }
        if identity_phrase {
            return IDENTITY_PHRASE_SCORE;
        }
        if tokens.iter().all(|token| all_tokens.contains(token)) {
            return FULL_COVERAGE_SCORE;
        }
        let matched = tokens
            .iter()
            .filter(|token| {
                all_tokens.contains(*token)
                    || (token.graphemes(true).count() >= MIN_PREFIX_GRAPHEMES
                        && all_tokens.iter().any(|word| {
                            word.graphemes(true).count() >= MIN_PREFIX_GRAPHEMES
                                && (word.starts_with(token.as_str()) || token.starts_with(word))
                        }))
            })
            .count();
        if matched == tokens.len() {
            PREFIX_COVERAGE_SCORE
        } else {
            PARTIAL_COVERAGE_SCORE * matched as f64 / tokens.len() as f64
        }
    }
}

/// Scores lexical evidence without embedding or memory history.
#[uniffi::export]
pub fn knowledge_lexical_score(
    entity: KnowledgeEntity,
    qualified_id: String,
    query: String,
) -> f64 {
    LexicalQuery::new(&query).score(&entity, &qualified_id)
}
