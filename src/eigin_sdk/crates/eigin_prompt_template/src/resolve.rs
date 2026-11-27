use super::{Templates, parser::Segment};
use std::collections::BTreeMap;

/// Resolves ordered required parameters and validates catalog-local includes.
/// Include chains are limited to 64 templates.
pub fn resolve_all_params(templates: &Templates) -> Result<BTreeMap<String, Vec<String>>, String> {
    let mut result = BTreeMap::new();
    let mut heights = BTreeMap::new();
    for name in templates.keys() {
        resolve(name, templates, &mut result, &mut heights, &mut Vec::new())?;
    }
    Ok(result)
}

fn resolve(
    name: &str,
    templates: &Templates,
    cache: &mut BTreeMap<String, Vec<String>>,
    heights: &mut BTreeMap<String, usize>,
    stack: &mut Vec<String>,
) -> Result<(Vec<String>, usize), String> {
    if stack.iter().any(|entry| entry == name) {
        return Err(format!("include cycle: {} -> {name}", stack.join(" -> ")));
    }
    if stack.len() >= 64 {
        return Err(format!("{name}: include depth exceeds 64"));
    }
    if let Some(params) = cache.get(name) {
        let height = heights[name];
        if stack.len() + height > 64 {
            return Err(format!("{name}: include depth exceeds 64"));
        }
        return Ok((params.clone(), height));
    }
    let segments = templates.get(name).ok_or_else(|| {
        format!(
            "included template `{name}` does not exist (from {})",
            stack.join(" -> ")
        )
    })?;
    stack.push(name.to_owned());
    let mut params = Vec::new();
    let mut includes = Vec::new();
    // Preserve first-occurrence ordering, including parameters from each include.
    visit(segments, &mut |parameter, include| {
        if include {
            let (nested, height) = resolve(parameter, templates, cache, heights, stack)?;
            includes.push(height);
            for value in nested {
                push_unique(&mut params, &value);
            }
        } else {
            push_unique(&mut params, parameter);
        }
        Ok(())
    })?;
    stack.pop();
    let height = 1 + includes.into_iter().max().unwrap_or(0);
    if height > 64 {
        return Err(format!("{name}: include depth exceeds 64"));
    }
    cache.insert(name.to_owned(), params.clone());
    heights.insert(name.to_owned(), height);
    Ok((params, height))
}

fn push_unique(params: &mut Vec<String>, value: &str) {
    if !params.iter().any(|p| p == value) {
        params.push(value.to_owned());
    }
}

fn visit(
    segments: &[Segment],
    f: &mut impl FnMut(&str, bool) -> Result<(), String>,
) -> Result<(), String> {
    for segment in segments {
        match segment {
            Segment::Text(_) => {}
            Segment::Var(name) => f(name, false)?,
            Segment::Include(name) => f(name, true)?,
            Segment::If { cond, then, els } => {
                f(cond, false)?;
                visit(then, f)?;
                visit(els, f)?;
            }
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parser;

    fn templates(entries: &[(&str, &str)]) -> Templates {
        entries
            .iter()
            .map(|(name, text)| (name.to_string(), parser::parse(text).unwrap()))
            .collect()
    }

    #[test]
    fn includes_contribute_parameters_in_first_use_order_without_duplicates() {
        let catalog = templates(&[
            (
                "greeting",
                "Hello {{ name }}!{% if role %}{% include 'details' %}{% endif %}{{ name }}",
            ),
            (
                "details",
                "{{ role }}{% if note %}{{ note }}{% else %}{{ fallback }}{% endif %}",
            ),
        ]);
        let parameters = resolve_all_params(&catalog).unwrap();
        assert_eq!(parameters["greeting"], ["name", "role", "note", "fallback"]);
        assert_eq!(parameters["details"], ["role", "note", "fallback"]);
    }

    #[test]
    fn reports_missing_includes_with_their_calling_template() {
        let error =
            resolve_all_params(&templates(&[("greeting", "{% include 'details' %}")])).unwrap_err();
        assert!(
            error.contains("details") && error.contains("greeting"),
            "{error}"
        );
    }

    #[test]
    fn rejects_cycles_even_in_an_unselected_branch() {
        let error = resolve_all_params(&templates(&[
            (
                "greeting",
                "{% if details %}{% include 'details' %}{% endif %}",
            ),
            ("details", "{% include 'greeting' %}"),
        ]))
        .unwrap_err();
        assert!(error.contains("cycle"), "{error}");
    }
}
