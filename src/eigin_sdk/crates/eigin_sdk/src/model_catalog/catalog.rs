use super::matching::{bare, matches, normalize};
use super::*;
use std::sync::{Arc, LazyLock};

/// Immutable curated catalog. The default is embedded in the SDK binary.
#[derive(uniffi::Object)]
pub struct ModelCatalog {
    entries: Vec<CatalogModelEntry>,
    ranking: Vec<String>,
    candidates: Vec<(usize, String, String)>,
}

impl ModelCatalog {
    pub(super) fn from_parts(entries: Vec<CatalogModelEntry>, ranking: Vec<String>) -> Self {
        let candidates = entries
            .iter()
            .enumerate()
            .flat_map(|(index, entry)| {
                std::iter::once(&entry.pattern)
                    .chain(&entry.aliases)
                    .map(move |s| (index, s.clone(), normalize(s)))
            })
            .collect();
        Self {
            entries,
            ranking,
            candidates,
        }
    }
}

#[uniffi::export]
impl ModelCatalog {
    /// Shared embedded catalog, prepared once without host services.
    #[uniffi::constructor]
    pub fn default_catalog() -> Arc<Self> {
        static DEFAULT: LazyLock<Arc<ModelCatalog>> =
            LazyLock::new(|| Arc::new(config::embedded()));
        DEFAULT.clone()
    }

    /// Ordered records; the first matching pattern or alias wins.
    pub fn entries(&self) -> Vec<CatalogModelEntry> {
        self.entries.clone()
    }

    /// Best-first offered-ID preference patterns.
    pub fn preference_ranking(&self) -> Vec<String> {
        self.ranking.clone()
    }

    /// Resolves an offered ID, retaining the matched alias and normalized version.
    pub fn lookup(&self, model_id: String) -> Option<CatalogModelMatch> {
        let id = bare(&model_id);
        let (index, raw, normalized) = self
            .candidates
            .iter()
            .find(|(_, _, pattern)| matches(&id, pattern))?;
        let suffix = id[normalized.len()..].trim_start_matches(['-', '@', ':']);
        Some(CatalogModelMatch {
            entry: self.entries[*index].clone(),
            matched: raw.clone(),
            version_tag: (!suffix.is_empty()).then(|| suffix.to_owned()),
        })
    }

    /// Recognized offers, retaining order, duplicates, and original IDs.
    pub fn known_models(&self, available: Vec<String>) -> Vec<String> {
        available
            .into_iter()
            .filter(|id| self.lookup(id.clone()).is_some())
            .collect()
    }

    /// Matches ranking patterns directly, then falls back to first known/first offer.
    pub fn best_model(&self, available: Vec<String>) -> Option<String> {
        for pattern in &self.ranking {
            let pattern = normalize(pattern);
            if let Some(id) = available.iter().find(|id| matches(&bare(id), &pattern)) {
                return Some(id.clone());
            }
        }
        available
            .iter()
            .find(|id| self.lookup((*id).clone()).is_some())
            .or(available.first())
            .cloned()
    }

    /// Rank of the resolved canonical pattern; unknown and unranked return none.
    pub fn preference_rank(&self, model_id: String) -> Option<u64> {
        let entry = self.lookup(model_id)?.entry;
        self.ranking
            .iter()
            .position(|s| *s == entry.pattern)
            .map(|i| i as u64)
    }

    /// Terciles across priced entries, with the existing small-catalog fallback.
    pub fn cost_terciles(&self) -> CatalogCostTerciles {
        let mut prices: Vec<_> = self
            .entries
            .iter()
            .filter_map(|e| e.output_cost_per_million)
            .collect();
        prices.sort_by(f64::total_cmp);
        if prices.len() < 3 {
            return CatalogCostTerciles {
                lower: 1.0,
                upper: 15.0,
            };
        }
        CatalogCostTerciles {
            lower: prices[(prices.len() - 1) / 3],
            upper: prices[(prices.len() - 1) * 2 / 3],
        }
    }
}
