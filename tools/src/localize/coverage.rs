use super::allowlist::Allowlist;

/// Why a key is counted as missing a translation.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MissingReason {
    /// The key has no localization entry for the required language.
    NoEntry,
    /// The entry exists but its string unit state is not "translated".
    NotTranslated,
}

/// A key that is missing a required translation (and is not allowlisted).
#[derive(Debug, Clone)]
pub struct MissingTranslation {
    pub key: String,
    pub lang: String,
    pub reason: MissingReason,
}

/// Result of the coverage check.
#[derive(Debug, Default)]
pub struct CoverageReport {
    /// Total keys scanned in the catalog.
    pub total_keys: usize,
    /// Keys missing a required language, not on the allowlist.
    pub missing: Vec<MissingTranslation>,
    /// Keys that were missing but are explicitly allowlisted.
    pub allowlisted: Vec<AllowlistedMissing>,
}

#[derive(Debug, Clone)]
pub struct AllowlistedMissing {
    pub key: String,
    pub lang: String,
}

impl CoverageReport {
    pub fn is_clean(&self) -> bool {
        self.missing.is_empty()
    }

    /// Friendly stderr summary for `just generate`. Non-blocking: never exits.
    /// Points the reader at the allowlist and config so the next step is
    /// actionable.
    pub fn print_warn(&self, allowlist_path: &str) {
        if self.missing.is_empty() {
            return;
        }
        // Group missing by key -> set of missing languages, for a compact list.
        let mut by_key: std::collections::BTreeMap<&str, Vec<&str>> = Default::default();
        for m in &self.missing {
            by_key.entry(&m.key).or_default().push(&m.lang);
        }
        eprintln!(
            "Found {} key(s) missing a required translation (out of {}):",
            by_key.len(),
            self.total_keys
        );
        for (key, langs) in &by_key {
            eprintln!("  {key} — missing {}", langs.join(", "));
        }
        eprintln!(
            "To fix: add a translation for each missing language, or add the key to the\n  allowlist at {allowlist_path} (configured as `localize.allowlist` in config/tools.toml)."
        );
    }
}

/// Scan a parsed xcstrings catalog for keys missing a required language.
///
/// A key is missing a language if it has no localizations entry for that
/// language, or the entry's string unit state is not "translated". Allowlisted
/// keys are moved to `allowlisted` and do not count against the report.
pub fn check(
    catalog: &serde_json::Value,
    required: &[String],
    allowlist: &Allowlist,
) -> CoverageReport {
    let strings = catalog["strings"].as_object();
    let total_keys = strings.map(|s| s.len()).unwrap_or(0);

    let mut report = CoverageReport {
        total_keys,
        ..Default::default()
    };

    let Some(strings) = strings else {
        return report;
    };

    for (key, value) in strings {
        // The skipped-key path handles entries with no localizations; reporting
        // them here as missing every language would be noise.
        let localizations = match value.get("localizations") {
            Some(l) if l.is_object() => l.as_object().unwrap(),
            _ => continue,
        };

        for lang in required {
            let entry = localizations.get(lang);
            let reason = match entry {
                None => Some(MissingReason::NoEntry),
                Some(e) => {
                    let state = e["stringUnit"]["state"].as_str();
                    if state == Some("translated") {
                        None
                    } else {
                        Some(MissingReason::NotTranslated)
                    }
                }
            };
            let Some(reason) = reason else { continue };

            if allowlist.keys.contains(key) {
                report.allowlisted.push(AllowlistedMissing {
                    key: key.clone(),
                    lang: lang.clone(),
                });
            } else {
                report.missing.push(MissingTranslation {
                    key: key.clone(),
                    lang: lang.clone(),
                    reason,
                });
            }
        }
    }

    // Sort for stable output: by key, then language.
    report
        .missing
        .sort_by(|a, b| a.key.cmp(&b.key).then(a.lang.cmp(&b.lang)));
    report
        .allowlisted
        .sort_by(|a, b| a.key.cmp(&b.key).then(a.lang.cmp(&b.lang)));
    report
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// Build a catalog where each key has the given translated languages.
    fn catalog_with(entries: &[(&str, &[(&str, &str)])]) -> serde_json::Value {
        let mut strings = serde_json::Map::new();
        for (key, langs) in entries {
            let mut localizations = serde_json::Map::new();
            for (lang, value) in *langs {
                localizations.insert(
                    lang.to_string(),
                    json!({ "stringUnit": { "state": "translated", "value": value } }),
                );
            }
            strings.insert(key.to_string(), json!({ "localizations": localizations }));
        }
        json!({ "sourceLanguage": "en", "strings": strings })
    }

    #[test]
    fn all_translated_is_clean() {
        let cat = catalog_with(&[("a.title", &[("en", "Title"), ("da", "Titel")])]);
        let report = check(&cat, &["en".into(), "da".into()], &Allowlist::default());
        assert!(report.is_clean());
    }

    #[test]
    fn missing_da_reported() {
        let cat = catalog_with(&[("a.title", &[("en", "Title")])]);
        let report = check(&cat, &["en".into(), "da".into()], &Allowlist::default());
        assert_eq!(report.missing.len(), 1);
        assert_eq!(report.missing[0].key, "a.title");
        assert_eq!(report.missing[0].lang, "da");
        assert_eq!(report.missing[0].reason, MissingReason::NoEntry);
    }

    #[test]
    fn not_translated_state_reported() {
        let cat = json!({
            "sourceLanguage": "en",
            "strings": {
                "a.title": {
                    "localizations": {
                        "en": { "stringUnit": { "state": "translated", "value": "Title" } },
                        "da": { "stringUnit": { "state": "new", "value": "Titel" } }
                    }
                }
            }
        });
        let report = check(&cat, &["en".into(), "da".into()], &Allowlist::default());
        assert_eq!(report.missing.len(), 1);
        assert_eq!(report.missing[0].reason, MissingReason::NotTranslated);
    }

    #[test]
    fn allowlisted_missing_is_suppressed() {
        let cat = catalog_with(&[("a.title", &[("en", "Title")])]);
        let mut keys = std::collections::HashSet::new();
        keys.insert("a.title".to_string());
        let allowlist = Allowlist { keys };
        let report = check(&cat, &["en".into(), "da".into()], &allowlist);
        assert!(report.is_clean());
        assert_eq!(report.allowlisted.len(), 1);
    }

    #[test]
    fn keys_without_localizations_are_skipped() {
        // A key with no localizations object is not flagged here; it's a
        // generator-skipped key, surfaced separately.
        let cat = json!({
            "sourceLanguage": "en",
            "strings": {
                "preview.sample": {},
                "a.title": {
                    "localizations": {
                        "en": { "stringUnit": { "state": "translated", "value": "Title" } },
                        "da": { "stringUnit": { "state": "translated", "value": "Titel" } }
                    }
                }
            }
        });
        let report = check(&cat, &["en".into(), "da".into()], &Allowlist::default());
        assert!(report.is_clean());
        assert_eq!(report.total_keys, 2);
    }

    #[test]
    fn missing_en_is_reported() {
        // Keys can be missing even the source language.
        let cat = catalog_with(&[("a.title", &[("da", "Titel")])]);
        let report = check(&cat, &["en".into(), "da".into()], &Allowlist::default());
        assert_eq!(report.missing.len(), 1);
        assert_eq!(report.missing[0].lang, "en");
    }
}
