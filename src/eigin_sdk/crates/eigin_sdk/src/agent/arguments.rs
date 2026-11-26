use serde::Deserialize;

// TODO(#430): Retire Foundation compatibility when SDK-owned tool parsing and execution share a contract.
/// Preserves Foundation's object parser acceptance without changing outgoing arguments.
pub(crate) fn valid_object(arguments: &str) -> bool {
    let input = arguments.strip_prefix('\u{feff}').unwrap_or(arguments);
    let bytes = input.as_bytes();
    let mut normalized = Vec::with_capacity(bytes.len());
    let mut in_string = false;
    let mut escaped = false;
    let mut depth = 0usize;
    for (index, &byte) in bytes.iter().enumerate() {
        if in_string {
            if escaped {
                escaped = false;
            } else if byte == b'\\' {
                escaped = true;
            } else if byte == b'"' {
                in_string = false;
            }
        } else {
            match byte {
                b'"' => in_string = true,
                b'{' | b'[' => {
                    depth += 1;
                    if depth > 512 {
                        return false;
                    }
                }
                b'}' | b']' => depth = depth.saturating_sub(1),
                b',' => {
                    let next = bytes[index + 1..].iter().find(|b| !b.is_ascii_whitespace());
                    let previous = normalized
                        .iter()
                        .rev()
                        .find(|b: &&u8| !b.is_ascii_whitespace());
                    if matches!(next, Some(b'}' | b']'))
                        && !matches!(previous, None | Some(b'{' | b'[' | b',' | b':'))
                    {
                        continue;
                    }
                }
                _ => {}
            }
        }
        normalized.push(byte);
    }
    let mut parser = serde_json::Deserializer::from_slice(&normalized);
    parser.disable_recursion_limit();
    serde_json::Value::deserialize(&mut parser).is_ok_and(|value| value.is_object())
        && parser.end().is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_foundation_object_extensions_without_changing_input() {
        for input in [
            "\u{feff}{}",
            "{\"a\":1,}",
            "{\"a\":[1,]}",
            "{\"a\":\",}\",}",
        ] {
            assert!(valid_object(input), "{input}");
        }
        for input in [
            "{,}",
            "{\"a\":1,,}",
            "{\"a\":,}",
            " \u{feff}{}",
            "{\"n\":1e999}",
            "{} false",
        ] {
            assert!(!valid_object(input), "{input}");
        }
    }

    #[test]
    fn accepts_up_to_512_nested_containers() {
        for depth in [128, 512, 513] {
            let input = format!("{}0{}", "{\"a\":".repeat(depth), "}".repeat(depth));
            assert_eq!(valid_object(&input), depth <= 512);
        }
    }
}
