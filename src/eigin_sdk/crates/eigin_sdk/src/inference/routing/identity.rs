// Swift identifier equality is canonical; retain original IDs in decisions.
// TODO(#458): review the identifier equality contract and normalization cost.
pub(super) fn key(value: &str) -> String {
    icu_normalizer::ComposingNormalizer::new_nfc()
        .normalize(value)
        .into_owned()
}

pub(super) fn equal(a: &str, b: &str) -> bool {
    key(a) == key(b)
}
