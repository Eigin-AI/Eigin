import Foundation

/// A parsed HTML `<form>`: where to POST it and its hidden field values.
///
/// The Aula/broker/MitID redirect chain hands off between hops via
/// auto-submitting HTML forms (SAML's HTTP-POST binding, and a "confirm
/// continue" page) rather than plain redirects. ``AulaFormWalker`` needs to
/// read and resubmit these without a browser, so we parse just enough HTML to
/// do that — no full DOM, just regex over the handful of shapes Aula's forms
/// take.
struct AulaHTMLForm: Equatable {
    /// The form's `action` attribute, or empty if the form omitted one (i.e.
    /// submit back to the current URL).
    let action: String
    /// Hidden `<input>` fields, in document order (duplicates keep the last
    /// value, matching browser form-submission semantics).
    let fields: [String: String]
}

/// Regex-based parsing of the small set of auto-submit form shapes seen in
/// Aula's UniLogin/MitID/SAML redirect chain — no HTML-parsing library, just
/// enough regex for a handful of fields. See `docs/src/integrations/aula.md`
/// for the headless flow this feeds.
enum AulaHTMLParsing {
    /// Extracts the SAML HTTP-POST binding form: the first `<form>` whose body
    /// contains a `SAMLResponse` hidden input.
    ///
    /// `RelayState` is tolerated as missing — Aula's Level 3 (`aula-sensitive`)
    /// flow sometimes omits it (community-reference issue #310).
    static func samlForm(in html: String) -> AulaHTMLForm? {
        guard let form = firstForm(in: html, containingField: "SAMLResponse") else {
            return nil
        }
        return form
    }

    /// Detects the broker's "confirm continue" page: present iff a
    /// `button#confirmation-button` appears in the HTML (community-reference
    /// issues #306/#287). Returns the form to resubmit, or nil on the normal
    /// happy path.
    static func confirmationForm(in html: String) -> AulaHTMLForm? {
        guard html.range(
            of: #"<button[^>]*\bid=["']confirmation-button["']"#,
            options: .regularExpression
        ) != nil
        else {
            return nil
        }
        return firstForm(in: html)
    }

    /// Any auto-submitting `<form>` on the page — used as a generic fallback
    /// hop when neither a SAML nor confirmation form shape matches, but the
    /// page is clearly a non-interactive redirect-via-form page.
    static func anyForm(in html: String) -> AulaHTMLForm? {
        firstForm(in: html)
    }

    // MARK: - Private

    /// Finds the first `<form>…</form>` block, optionally requiring a named
    /// hidden field to appear inside it, and extracts its `action` plus all
    /// hidden field values.
    private static func firstForm(
        in html: String,
        containingField: String? = nil
    ) -> AulaHTMLForm? {
        let formPattern = #"<form\b[^>]*\baction\s*=\s*(?:"([^"]*)"|'([^']*)')?[^>]*>([\s\S]*?)</form>"#
        guard let regex = try? NSRegularExpression(
            pattern: formPattern,
            options: [.caseInsensitive]
        ) else { return nil }

        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        for match in matches {
            let body = match.range(at: 3).location != NSNotFound
                ? nsHTML.substring(with: match.range(at: 3))
                : ""

            if let containingField {
                guard body.range(
                    of: #"name\s*=\s*["']\#(NSRegularExpression.escapedPattern(for: containingField))["']"#,
                    options: .regularExpression
                ) != nil else { continue }
            }

            let action: String = if match.range(at: 1).location != NSNotFound {
                nsHTML.substring(with: match.range(at: 1))
            } else if match.range(at: 2).location != NSNotFound {
                nsHTML.substring(with: match.range(at: 2))
            } else {
                ""
            }

            return AulaHTMLForm(action: action, fields: hiddenInputs(in: body))
        }
        return nil
    }

    /// Extracts `name`/`value` pairs from `<input type="hidden" ...>` tags
    /// (attribute order-independent), decoding HTML entities in values.
    private static func hiddenInputs(in html: String) -> [String: String] {
        let pattern = #"<input\b[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return [:] }

        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        var result: [String: String] = [:]
        for match in matches {
            let tag = nsHTML.substring(with: match.range)
            guard tag.range(
                of: #"type\s*=\s*["']hidden["']"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil else { continue }

            guard let name = attribute("name", in: tag) else { continue }
            result[name] = decodeHTMLEntities(attribute("value", in: tag) ?? "")
        }
        return result
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = #"\#(name)\s*=\s*(?:"([^"]*)"|'([^']*)')"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(
                  in: tag,
                  range: NSRange(location: 0, length: (tag as NSString).length)
              )
        else { return nil }

        let nsTag = tag as NSString
        if match.range(at: 1).location != NSNotFound {
            return nsTag.substring(with: match.range(at: 1))
        }
        if match.range(at: 2).location != NSNotFound {
            return nsTag.substring(with: match.range(at: 2))
        }
        return nil
    }

    private static func decodeHTMLEntities(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
