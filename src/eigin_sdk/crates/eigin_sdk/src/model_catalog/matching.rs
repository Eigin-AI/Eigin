use icu_properties::{CodePointMapData, props::NumericType};
use unicode_segmentation::UnicodeSegmentation;

pub(super) fn bare(id: &str) -> String {
    normalize(id.split_once('/').map_or(id, |(_, tail)| tail))
}

pub(super) fn normalize(id: &str) -> String {
    let mut value = id.to_lowercase().replace('.', "-");
    for suffix in [
        "-fp8", "-fp16", "-bf16", "-int8", "-int4", "-awq", "-gptq", "-gguf",
    ] {
        if value.ends_with(suffix) {
            value.truncate(value.len() - suffix.len());
            break;
        }
    }
    value
}

pub(super) fn matches(id: &str, pattern: &str) -> bool {
    let Some(suffix) = id.strip_prefix(pattern) else {
        return false;
    };
    if suffix.is_empty() {
        return true;
    }
    let mut characters = suffix.graphemes(true);
    let first = characters.next().unwrap();
    let digit = if matches!(first, "-" | ":" | "@") {
        characters.next()
    } else {
        Some(first)
    };
    digit.is_some_and(|s| {
        s.chars()
            .next()
            .is_some_and(|c| CodePointMapData::<NumericType>::new().get(c) != NumericType::None)
    })
}
