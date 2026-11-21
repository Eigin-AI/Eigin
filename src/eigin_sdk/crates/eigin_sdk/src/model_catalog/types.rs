use serde::Deserialize;

/// Catalog family, independent of inference-adapter selection.
#[derive(Clone, Debug, PartialEq, Eq, Deserialize, uniffi::Enum)]
#[serde(rename_all = "lowercase")]
pub enum CatalogModelFamily {
    OpenAi,
    Anthropic,
    Google,
    Mistral,
    Grok,
    Zhipu,
    Moonshot,
    Alibaba,
    Minimax,
    Deepseek,
    Apple,
    Gemma,
    Nvidia,
    Corti,
}

/// Shared reasoning wire vocabulary, ordered by effort.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Deserialize, uniffi::Enum)]
#[serde(rename_all = "lowercase")]
pub enum CatalogReasoningEffort {
    None,
    Minimal,
    Low,
    Medium,
    High,
    Xhigh,
    Max,
}

/// Verified model effort settings.
#[derive(Clone, Debug, PartialEq, Deserialize, uniffi::Record)]
#[serde(deny_unknown_fields)]
pub struct CatalogReasoningControl {
    pub supported_efforts: Vec<CatalogReasoningEffort>,
    pub fast_effort: CatalogReasoningEffort,
    pub escalated_effort: CatalogReasoningEffort,
    pub default_effort: Option<CatalogReasoningEffort>,
}

impl CatalogReasoningControl {
    /// Applies the default and caps supported or unsupported requests.
    pub fn request_effort(
        &self,
        requested: Option<CatalogReasoningEffort>,
    ) -> Option<CatalogReasoningEffort> {
        let effort = requested.or(self.default_effort)?;
        Some(if self.supported_efforts.contains(&effort) {
            effort.min(self.escalated_effort)
        } else {
            self.escalated_effort
        })
    }
}

/// Curated metadata for one ordered model pattern and its aliases.
#[derive(Clone, Debug, PartialEq, Deserialize, uniffi::Record)]
#[serde(deny_unknown_fields)]
pub struct CatalogModelEntry {
    pub pattern: String,
    #[serde(default)]
    pub aliases: Vec<String>,
    pub display_name: String,
    pub family: CatalogModelFamily,
    pub context_window: i64,
    pub max_output: Option<i64>,
    pub input_cost_per_million: Option<f64>,
    pub output_cost_per_million: Option<f64>,
    pub supports_tool_call: bool,
    pub supports_reasoning: bool,
    pub supports_vision: bool,
    pub is_recommended: bool,
    pub reasoning_control: Option<CatalogReasoningControl>,
}

/// Resolved metadata with the exact catalog candidate that matched.
#[derive(Clone, Debug, uniffi::Record)]
pub struct CatalogModelMatch {
    pub entry: CatalogModelEntry,
    pub matched: String,
    pub version_tag: Option<String>,
}

/// Output-price thresholds for relative cost badges.
#[derive(Clone, Debug, uniffi::Record)]
pub struct CatalogCostTerciles {
    pub lower: f64,
    pub upper: f64,
}
