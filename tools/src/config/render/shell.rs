use std::fmt::Write;

/// Write a shell `export` line whose value survives `eval` verbatim.
pub fn export(out: &mut String, key: &str, value: &str) {
    let _ = writeln!(out, "export {key}={}", quote(value));
}

/// Single-quote a value for POSIX shells.
///
/// Renderer output is consumed with `eval`, so double quotes would let `$` and
/// backticks in a secret expand or execute. Single quotes suppress all of that;
/// the only character needing care is the single quote itself, which is closed,
/// escaped and reopened.
pub fn quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', r"'\''"))
}

/// Read rendered exports back as key/value pairs.
///
/// For callers that set the environment themselves rather than handing the
/// block to a shell: the dev-loop commands spawn xcodebuild and the relay
/// directly, with no `eval` in between.
pub fn parse_exports(rendered: &str) -> Vec<(String, String)> {
    rendered
        .lines()
        .filter_map(|line| line.strip_prefix("export "))
        .filter_map(|line| line.split_once('='))
        .map(|(key, value)| (key.to_string(), unquote(value)))
        .collect()
}

fn unquote(value: &str) -> String {
    match value.strip_prefix('\'').and_then(|v| v.strip_suffix('\'')) {
        Some(inner) => inner.replace(r"'\''", "'"),
        None => value.to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Round-trip a value through a real shell exactly the way the justfile does:
    /// the rendered exports arrive in a variable, which is then `eval "$vars"`-ed.
    /// The value is never inlined into the script text — that would add a parse
    /// the real call site doesn't have, and would wrongly fail these tests.
    fn eval_back(value: &str) -> String {
        let mut rendered = String::new();
        export(&mut rendered, "V", value);
        let out = std::process::Command::new("sh")
            .args(["-c", r#"eval "$RENDERED"; printf '%s' "$V""#])
            .env("RENDERED", rendered)
            .output()
            .expect("running sh");
        String::from_utf8_lossy(&out.stdout).to_string()
    }

    #[test]
    fn plain_values_round_trip() {
        assert_eq!(eval_back("abc123"), "abc123");
    }

    #[test]
    fn dollar_signs_are_not_expanded() {
        assert_eq!(eval_back("abc$HOME-def"), "abc$HOME-def");
    }

    #[test]
    fn backticks_are_not_executed() {
        assert_eq!(eval_back("tick`echo PWNED`"), "tick`echo PWNED`");
    }

    #[test]
    fn command_substitution_is_not_executed() {
        assert_eq!(eval_back("a$(echo PWNED)b"), "a$(echo PWNED)b");
    }

    #[test]
    fn embedded_single_quotes_survive() {
        assert_eq!(eval_back("it's \"quoted\""), "it's \"quoted\"");
    }

    #[test]
    fn empty_value_round_trips() {
        assert_eq!(eval_back(""), "");
    }

    /// The pair form has to agree with the shell form, or the dev-loop commands
    /// and the recipes that `eval` would disagree about the same secret.
    fn parse_back(value: &str) -> String {
        let mut rendered = String::new();
        export(&mut rendered, "V", value);
        parse_exports(&rendered).remove(0).1
    }

    #[test]
    fn parsing_matches_what_a_shell_would_see() {
        for value in [
            "abc123",
            "abc$HOME-def",
            "tick`echo PWNED`",
            "it's \"quoted\"",
            "",
            "a=b=c",
        ] {
            assert_eq!(parse_back(value), eval_back(value), "value: {value}");
        }
    }

    #[test]
    fn parsing_keeps_the_key() {
        let mut rendered = String::new();
        export(&mut rendered, "BUNDLE_ID", "ai.eigin.finch");
        assert_eq!(
            parse_exports(&rendered),
            vec![("BUNDLE_ID".to_string(), "ai.eigin.finch".to_string())]
        );
    }
}
