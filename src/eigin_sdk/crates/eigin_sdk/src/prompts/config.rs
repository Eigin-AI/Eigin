use super::{
    catalog::PromptCatalog,
    template::{Templates, parser, resolve_all_params},
};
use serde::{Deserialize, Deserializer, de};
use std::collections::BTreeMap;
use std::fmt;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Document {
    schema_version: u32,
    #[serde(deserialize_with = "unique_templates")]
    templates: BTreeMap<String, String>,
}

fn unique_templates<'de, D: Deserializer<'de>>(
    deserializer: D,
) -> Result<BTreeMap<String, String>, D::Error> {
    struct Unique;
    impl<'de> de::Visitor<'de> for Unique {
        type Value = BTreeMap<String, String>;
        fn expecting(&self, formatter: &mut fmt::Formatter) -> fmt::Result {
            formatter.write_str("a map of unique template names to strings")
        }
        fn visit_map<M: de::MapAccess<'de>>(self, mut map: M) -> Result<Self::Value, M::Error> {
            let mut templates = BTreeMap::new();
            while let Some((key, value)) = map.next_entry::<String, String>()? {
                if key.is_empty() {
                    return Err(de::Error::custom("empty template name"));
                }
                if templates.insert(key.clone(), value).is_some() {
                    return Err(de::Error::custom(format!("duplicate template `{key}`")));
                }
            }
            Ok(templates)
        }
    }
    deserializer.deserialize_map(Unique)
}

pub(super) fn load(source: &str) -> Result<PromptCatalog, String> {
    let document: Document = serde_json::from_str(source).map_err(|e| e.to_string())?;
    if document.schema_version != 1 {
        return Err("unsupported catalog schema version".into());
    }
    let templates: Templates = document
        .templates
        .into_iter()
        .map(|(name, source)| {
            parser::parse(&source)
                .map(|segments| (name.clone(), segments))
                .map_err(|e| format!("{name}: {e}"))
        })
        .collect::<Result<_, _>>()?;
    let parameters = resolve_all_params(&templates)?;
    Ok(PromptCatalog {
        templates,
        parameters,
    })
}
