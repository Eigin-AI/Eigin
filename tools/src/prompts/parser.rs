pub use eigin_prompt_template::parser::Segment;

/// Parse with the SDK's shared limited template syntax.
pub fn parse(source: &str) -> anyhow::Result<Vec<Segment>> {
    eigin_prompt_template::parser::parse(source).map_err(anyhow::Error::msg)
}
