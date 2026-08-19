//! Typed `Content-Security-Policy` builder.
//!
//! Call sites set named directives from typed [`Source`] values instead of
//! hand-writing the semicolon/space-joined string, so a typo in a keyword
//! (e.g. `none` instead of `'none'`) can't silently produce a weaker policy.

use axum::http::HeaderValue;

/// A single CSP source expression. Standard keywords are typed variants;
/// [`Source::Host`] is the escape hatch for a specific origin or scheme
/// (e.g. `https://cdn.jsdelivr.net`, `https:`) that isn't a fixed keyword.
pub enum Source {
    None,
    SelfOrigin,
    UnsafeInline,
    UnsafeEval,
    Data,
    Host(&'static str),
}

impl Source {
    fn as_str(&self) -> &str {
        match self {
            Source::None => "'none'",
            Source::SelfOrigin => "'self'",
            Source::UnsafeInline => "'unsafe-inline'",
            Source::UnsafeEval => "'unsafe-eval'",
            Source::Data => "data:",
            Source::Host(host) => host,
        }
    }
}

/// Builds a `Content-Security-Policy` header value from named directives.
#[derive(Default)]
pub struct ContentSecurityPolicy {
    directives: Vec<(&'static str, String)>,
}

impl ContentSecurityPolicy {
    /// Starts an empty policy.
    pub fn new() -> Self {
        Self::default()
    }

    /// Sets a directive to a list of sources, space-joined.
    pub fn directive(mut self, name: &'static str, sources: &[Source]) -> Self {
        let joined = sources
            .iter()
            .map(Source::as_str)
            .collect::<Vec<_>>()
            .join(" ");
        self.directives.push((name, joined));
        self
    }

    pub fn default_src(self, sources: &[Source]) -> Self {
        self.directive("default-src", sources)
    }

    pub fn script_src(self, sources: &[Source]) -> Self {
        self.directive("script-src", sources)
    }

    pub fn style_src(self, sources: &[Source]) -> Self {
        self.directive("style-src", sources)
    }

    pub fn font_src(self, sources: &[Source]) -> Self {
        self.directive("font-src", sources)
    }

    pub fn img_src(self, sources: &[Source]) -> Self {
        self.directive("img-src", sources)
    }

    pub fn connect_src(self, sources: &[Source]) -> Self {
        self.directive("connect-src", sources)
    }

    pub fn frame_ancestors(self, sources: &[Source]) -> Self {
        self.directive("frame-ancestors", sources)
    }

    /// Renders the policy as a header value.
    pub fn into_header_value(self) -> HeaderValue {
        let value = self
            .directives
            .iter()
            .map(|(name, sources)| format!("{name} {sources}"))
            .collect::<Vec<_>>()
            .join("; ");
        HeaderValue::from_str(&value).expect("CSP directives must be valid header characters")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn joins_directives_with_semicolons() {
        let csp = ContentSecurityPolicy::new()
            .default_src(&[Source::None])
            .frame_ancestors(&[Source::None])
            .into_header_value();

        assert_eq!(csp, "default-src 'none'; frame-ancestors 'none'");
    }

    #[test]
    fn joins_sources_within_a_directive_with_spaces() {
        let csp = ContentSecurityPolicy::new()
            .script_src(&[Source::SelfOrigin, Source::Host("https://cdn.jsdelivr.net")])
            .into_header_value();

        assert_eq!(csp, "script-src 'self' https://cdn.jsdelivr.net");
    }
}
