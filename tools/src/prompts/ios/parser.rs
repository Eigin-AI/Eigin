use anyhow::{Result, bail};

/// A parsed fragment of a prompt template.
///
/// Templates support a deliberately small subset of Jinja: bare variable
/// substitution, emptiness conditionals, and build-time composition via
/// includes. Loops, filters, operators, and attribute access are rejected so
/// the generator stays a simple variables-and-includes mapping rather than a
/// control-flow transpiler.
#[derive(Debug, Clone, PartialEq)]
pub enum Segment {
    /// Literal text, emitted verbatim.
    Text(String),
    /// `{{ name }}` — a `String` substitution.
    Var(String),
    /// `{% include "rel/path.jinja" %}` — composed at build time.
    Include(String),
    /// `{% if cond %}then{% else %}els{% endif %}` — `cond` is a `String`,
    /// truthy when non-empty.
    If {
        cond: String,
        then: Vec<Segment>,
        els: Vec<Segment>,
    },
}

/// Parse a template's source into segments, validating the supported subset.
pub fn parse(src: &str) -> Result<Vec<Segment>> {
    let tokens = tokenize(src)?;
    let mut pos = 0;
    let segments = build_segments(&tokens, &mut pos, false)?;
    Ok(segments)
}

#[derive(Debug, PartialEq)]
enum Token {
    Text(String),
    Var(String),
    Include(String),
    If(String),
    Else,
    Endif,
}

fn is_ident(s: &str) -> bool {
    let mut chars = s.chars();
    match chars.next() {
        Some(c) if c.is_ascii_alphabetic() || c == '_' => {}
        _ => return false,
    }
    chars.all(|c| c.is_ascii_alphanumeric() || c == '_')
}

fn tokenize(src: &str) -> Result<Vec<Token>> {
    let mut tokens = Vec::new();
    let mut i = 0;
    let mut text_start = 0;

    while i < src.len() {
        let tail = &src[i..];
        let delim = if tail.starts_with("{{") {
            Some(("{{", "}}"))
        } else if tail.starts_with("{%") {
            Some(("{%", "%}"))
        } else if tail.starts_with("{#") {
            Some(("{#", "#}"))
        } else {
            None
        };

        let Some((open, close)) = delim else {
            // Advance one UTF-8 character.
            i += tail.chars().next().unwrap().len_utf8();
            continue;
        };

        if i > text_start {
            tokens.push(Token::Text(src[text_start..i].to_string()));
        }

        let rest = &src[i + open.len()..];
        let end = rest
            .find(close)
            .ok_or_else(|| anyhow::anyhow!("unclosed `{open}` tag"))?;
        let inner = rest[..end].trim();

        match open {
            "{{" => {
                if !is_ident(inner) {
                    bail!(
                        "unsupported expression `{{{{ {inner} }}}}` — only bare variables are allowed (no filters, attributes, or operators)"
                    );
                }
                tokens.push(Token::Var(inner.to_string()));
            }
            "{%" => parse_tag(inner, &mut tokens)?,
            _ => {} // `{# comment #}` — drop.
        }

        i += open.len() + end + close.len();
        text_start = i;
    }

    if text_start < src.len() {
        tokens.push(Token::Text(src[text_start..].to_string()));
    }

    Ok(tokens)
}

fn parse_tag(inner: &str, tokens: &mut Vec<Token>) -> Result<()> {
    let mut parts = inner.splitn(2, char::is_whitespace);
    let keyword = parts.next().unwrap_or("");
    let arg = parts.next().map(str::trim).unwrap_or("");

    match keyword {
        "if" => {
            if !is_ident(arg) {
                bail!(
                    "unsupported condition `{{% if {arg} %}}` — only `{{% if <variable> %}}` is supported (no operators or filters)"
                );
            }
            tokens.push(Token::If(arg.to_string()));
        }
        "else" => {
            if !arg.is_empty() {
                bail!("`{{% else %}}` takes no arguments");
            }
            tokens.push(Token::Else);
        }
        "endif" => {
            if !arg.is_empty() {
                bail!("`{{% endif %}}` takes no arguments");
            }
            tokens.push(Token::Endif);
        }
        "include" => tokens.push(Token::Include(parse_string_literal(arg)?)),
        other => bail!(
            "unsupported tag `{{% {other} ... %}}` — only if/else/endif/include are allowed (no loops, set, macros, or filters)"
        ),
    }

    Ok(())
}

fn parse_string_literal(arg: &str) -> Result<String> {
    let arg = arg.trim();
    let quoted = (arg.starts_with('"') && arg.ends_with('"'))
        || (arg.starts_with('\'') && arg.ends_with('\''));
    if quoted && arg.len() >= 2 {
        Ok(arg[1..arg.len() - 1].to_string())
    } else {
        bail!("include target must be a quoted path, got `{arg}`")
    }
}

fn build_segments(tokens: &[Token], pos: &mut usize, in_block: bool) -> Result<Vec<Segment>> {
    let mut segments = Vec::new();

    while *pos < tokens.len() {
        match &tokens[*pos] {
            Token::Text(t) => {
                segments.push(Segment::Text(t.clone()));
                *pos += 1;
            }
            Token::Var(v) => {
                segments.push(Segment::Var(v.clone()));
                *pos += 1;
            }
            Token::Include(p) => {
                segments.push(Segment::Include(p.clone()));
                *pos += 1;
            }
            Token::If(cond) => {
                let cond = cond.clone();
                *pos += 1;
                let then = build_segments(tokens, pos, true)?;
                let mut els = Vec::new();
                match tokens.get(*pos) {
                    Some(Token::Else) => {
                        *pos += 1;
                        els = build_segments(tokens, pos, true)?;
                        expect_endif(tokens, pos)?;
                    }
                    Some(Token::Endif) => *pos += 1,
                    _ => bail!("missing `{{% endif %}}`"),
                }
                segments.push(Segment::If { cond, then, els });
            }
            Token::Else | Token::Endif => {
                if in_block {
                    return Ok(segments);
                }
                bail!("`{{% else %}}`/`{{% endif %}}` without a matching `{{% if %}}`");
            }
        }
    }

    if in_block {
        bail!("missing `{{% endif %}}`");
    }
    Ok(segments)
}

fn expect_endif(tokens: &[Token], pos: &mut usize) -> Result<()> {
    match tokens.get(*pos) {
        Some(Token::Endif) => {
            *pos += 1;
            Ok(())
        }
        _ => bail!("missing `{{% endif %}}`"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_text() {
        assert_eq!(
            parse("hello world").unwrap(),
            vec![Segment::Text("hello world".into())]
        );
    }

    #[test]
    fn variable_substitution() {
        assert_eq!(
            parse("Hi {{ name }}!").unwrap(),
            vec![
                Segment::Text("Hi ".into()),
                Segment::Var("name".into()),
                Segment::Text("!".into()),
            ]
        );
    }

    #[test]
    fn include_tag() {
        assert_eq!(
            parse("{% include \"system/behavioral.jinja\" %}").unwrap(),
            vec![Segment::Include("system/behavioral.jinja".into())]
        );
    }

    #[test]
    fn if_else_block() {
        let segs = parse("a{% if x %}b{% else %}c{% endif %}d").unwrap();
        assert_eq!(
            segs,
            vec![
                Segment::Text("a".into()),
                Segment::If {
                    cond: "x".into(),
                    then: vec![Segment::Text("b".into())],
                    els: vec![Segment::Text("c".into())],
                },
                Segment::Text("d".into()),
            ]
        );
    }

    #[test]
    fn nested_if() {
        let segs = parse("{% if a %}{% if b %}x{% endif %}{% endif %}").unwrap();
        assert_eq!(
            segs,
            vec![Segment::If {
                cond: "a".into(),
                then: vec![Segment::If {
                    cond: "b".into(),
                    then: vec![Segment::Text("x".into())],
                    els: vec![],
                }],
                els: vec![],
            }]
        );
    }

    #[test]
    fn comments_are_dropped() {
        assert_eq!(
            parse("a{# note #}b").unwrap(),
            vec![Segment::Text("a".into()), Segment::Text("b".into())]
        );
    }

    #[test]
    fn rejects_filters() {
        assert!(parse("{{ name | upper }}").is_err());
    }

    #[test]
    fn rejects_attribute_access() {
        assert!(parse("{{ intent.content }}").is_err());
    }

    #[test]
    fn rejects_for_loop() {
        assert!(parse("{% for x in xs %}{{ x }}{% endfor %}").is_err());
    }

    #[test]
    fn rejects_set() {
        assert!(parse("{% set x = 1 %}").is_err());
    }

    #[test]
    fn rejects_unbalanced_if() {
        assert!(parse("{% if x %}no end").is_err());
        assert!(parse("dangling{% endif %}").is_err());
    }

    #[test]
    fn rejects_unclosed_delimiter() {
        assert!(parse("{{ name ").is_err());
    }
}
