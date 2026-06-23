import Foundation

/// Converts written text into spoken form using locale-specific rules.
///
/// Handles numbers, currencies, times, dates, units, and abbreviations.
/// Applied after markdown stripping, before text reaches the TTS engine.
enum SpokenTextNormalizer {
    /// Normalize text for speech using the given locale rules.
    static func normalize(_ text: String, locale: SpokenTextLocale) -> String {
        var result = text
        result = processURLsAndDomains(result, locale: locale)
        result = processVersionNumbers(result, locale: locale)
        result = processScaleAbbreviations(result, locale: locale)
        result = removeCommasFromNumbers(result)
        result = processRanges(result, locale: locale)
        result = processCurrencies(result, locale: locale)
        result = processTimes(result, locale: locale)
        result = processUnitAbbreviations(result, locale: locale)
        result = processDecimalNumbers(result, locale: locale)
        result = processOrdinalDates(result, locale: locale)
        result = processAlphanumericCodes(result, locale: locale)
        result = processCommonAbbreviations(result, locale: locale)
        result = spellOutWholeNumbers(result, locale: locale)
        result = stripNonSpeechCharacters(result, locale: locale)
        result = tidyPunctuation(result)
        return result
    }

    // MARK: - URLs and Domains

    /// Matches full URLs: https://example.com/path or http://example.com
    private static let fullURLRegex = try! NSRegularExpression(
        pattern: #"https?://[^\s,;)>]+"#, options: .caseInsensitive
    )

    /// Matches bare domains: github.com, www.site.cool.com
    /// Requires at least one dot and a known TLD or www prefix.
    private static let bareDomainRegex = try! NSRegularExpression(
        pattern: #"\b(?:www\.)?[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.(?:com|org|net|io|dev|app|ai|co|dk|uk|de|eu|info|me|tv|se|no|fi|is)\b"#,
        options: .caseInsensitive
    )

    /// Convert URLs and domains to spoken form.
    /// Full URLs are reduced to just the domain. Dots become the locale's dot word.
    private static func processURLsAndDomains(_ text: String, locale: SpokenTextLocale) -> String {
        var result = text

        // First handle full URLs — extract just the domain.
        let fullMatches = fullURLRegex.matches(
            in: result, range: NSRange(location: 0, length: result.utf16.count)
        )
        for match in fullMatches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let url = String(result[range])
            let domain = url
                .replacingOccurrences(of: "https://", with: "", options: .caseInsensitive)
                .replacingOccurrences(of: "http://", with: "", options: .caseInsensitive)
                .components(separatedBy: "/").first ?? url
            result.replaceSubrange(range, with: spellDomain(domain, dotWord: locale.dotWord))
        }

        // Then handle bare domains that weren't part of URLs.
        let bareMatches = bareDomainRegex.matches(
            in: result, range: NSRange(location: 0, length: result.utf16.count)
        )
        for match in bareMatches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let domain = String(result[range])
            result.replaceSubrange(range, with: spellDomain(domain, dotWord: locale.dotWord))
        }

        return result
    }

    private static func spellDomain(_ domain: String, dotWord: String) -> String {
        let parts = domain.components(separatedBy: ".")
        return parts.map { part in
            if part.lowercased() == "www" {
                return "w w w"
            }
            return part
        }.joined(separator: " \(dotWord) ")
    }

    // MARK: - Version Numbers

    /// Matches version strings: v1.2.3, 1.3.5, v2.0
    /// Must have at least two dot-separated components and optional "v" prefix.
    private static let versionRegex = try! NSRegularExpression(
        pattern: #"\bv?(\d+(?:\.\d+){2,})\b"#, options: .caseInsensitive
    )

    /// "v1.2.3" → "v one point two point three", "1.3.5" → "one point three point five"
    private static func processVersionNumbers(_ text: String, locale: SpokenTextLocale) -> String {
        let matches = versionRegex.matches(
            in: text, range: NSRange(location: 0, length: text.utf16.count)
        )

        var result = text
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let numRange = Range(match.range(at: 1), in: result)
            else { continue }

            let fullMatch = String(result[fullRange])
            let hasPrefix = fullMatch.lowercased().hasPrefix("v")
            let numPart = String(result[numRange])

            let parts = numPart.components(separatedBy: ".")
            let spoken = parts.compactMap { component -> String? in
                guard let val = Int(component) else { return component }
                return locale.numberFormatter.string(from: NSNumber(value: val)) ?? component
            }.joined(separator: " \(locale.pointWord) ")

            let replacement = hasPrefix ? "v \(spoken)" : spoken
            result.replaceSubrange(fullRange, with: replacement)
        }
        return result
    }

    // MARK: - Scale Abbreviations

    /// Matches number + scale suffix: 100M, 1.5B, 7B, 100K
    private static let scaleRegex = try! NSRegularExpression(
        pattern: #"\b(\d+(?:\.\d+)?)\s*(K|M|B|T)\b"#
    )

    /// "100M parameters" → "one hundred million parameters"
    private static func processScaleAbbreviations(
        _ text: String,
        locale: SpokenTextLocale
    ) -> String {
        let matches = scaleRegex.matches(
            in: text, range: NSRange(location: 0, length: text.utf16.count)
        )

        var result = text
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let numRange = Range(match.range(at: 1), in: result),
                  let suffixRange = Range(match.range(at: 2), in: result)
            else { continue }

            let numStr = String(result[numRange])
            let suffix = String(result[suffixRange])

            guard let scaleWord = locale.scaleWords[suffix] else { continue }

            // Spell the number part
            let numWord: String
            if let intVal = Int(numStr) {
                numWord = locale.numberFormatter.string(from: NSNumber(value: intVal)) ?? numStr
            } else if Double(numStr) != nil {
                // Handle decimals like "1.5B" → "one point five billion"
                let parts = numStr.components(separatedBy: ".")
                let intPart = locale.numberFormatter
                    .string(from: NSNumber(value: Int(parts[0]) ?? 0)) ?? parts[0]
                let decPart = parts.count > 1 ? parts[1].compactMap { char -> String? in
                    guard let d = char.wholeNumberValue,
                          d < locale.digitWords.count else { return nil }
                    return locale.digitWords[d]
                }.joined(separator: " ") : ""
                numWord = decPart.isEmpty ? intPart : "\(intPart) \(locale.pointWord) \(decPart)"
            } else {
                numWord = numStr
            }

            result.replaceSubrange(fullRange, with: "\(numWord) \(scaleWord)")
        }
        return result
    }

    // MARK: - Structural Cleanup

    /// Replace symbols with spoken equivalents, then strip remaining
    /// non-speech characters. Runs last so earlier steps can still
    /// match symbols like $ and °.
    private static func stripNonSpeechCharacters(
        _ text: String,
        locale: SpokenTextLocale
    ) -> String {
        var result = text
        // Replace meaningful symbols with spoken words or spaces.
        result = result.replacingOccurrences(of: "~", with: "\(locale.approximatelyWord) ")
        result = result.replacingOccurrences(of: "/", with: " ")
        result = result.replacingOccurrences(of: "_", with: " ")
        result = result.replacingOccurrences(of: "(", with: ", ")
        result = result.replacingOccurrences(of: ")", with: ", ")
        result = result.replacingOccurrences(of: "=", with: " ")
        // Table cell separators become comma pauses; the tidy pass below trims
        // the leading/trailing commas left by a row's outer pipes.
        result = result.replacingOccurrences(of: "|", with: ", ")
        // Strip remaining non-speech characters: keep letters, digits,
        // whitespace, and sentence punctuation (.!?,;:'-).
        result = String(result.unicodeScalars.filter { scalar in
            scalar.properties.isAlphabetic
                || scalar.value >= 0x30 && scalar.value <= 0x39 // digits
                || scalar == " " || scalar == "\n" || scalar == "\t"
                || ".,;:!?'-".unicodeScalars.contains(scalar)
        })
        // Collapse multiple spaces left by removals.
        result = multiSpaceRegex.stringByReplacingMatches(
            in: result, range: NSRange(location: 0, length: result.utf16.count), withTemplate: " "
        )
        result = result.trimmingCharacters(in: .whitespaces)
        return result
    }

    private static let multiSpaceRegex = try! NSRegularExpression(pattern: #" {2,}"#)

    /// Matches a run of sentence punctuation (optionally separated by spaces),
    /// plus any whitespace immediately preceding it. Captures the marks so the
    /// run can be collapsed to a single strongest one.
    private static let punctuationRunRegex = try! NSRegularExpression(
        pattern: #"\s*([,.;:!?](?:\s*[,.;:!?])*)"#
    )

    /// A dangling separator at the very start of the text (e.g. a table row's
    /// leading outer pipe, now a comma).
    private static let leadingSeparatorRegex = try! NSRegularExpression(pattern: #"^[\s,;:]+"#)
    /// A dangling separator at the very end of the text, keeping sentence-ending
    /// `.!?` but dropping a trailing comma or semicolon.
    private static let trailingSeparatorRegex = try! NSRegularExpression(pattern: #"[\s,;]+$"#)

    /// Collapse redundant punctuation left behind by earlier rules (notably the
    /// `(` / `)` -> `, ` conversion). Removes whitespace before punctuation and
    /// reduces any run of marks to the single strongest one: `.!?` beat `:;`,
    /// which beat `,`. So `", ,"` -> `","`, `", :"` -> `":"`, `":."` -> `"."`.
    private static func tidyPunctuation(_ text: String) -> String {
        let range = NSRange(location: 0, length: text.utf16.count)
        let matches = punctuationRunRegex.matches(in: text, range: range)

        var result = text
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let marksRange = Range(match.range(at: 1), in: result)
            else { continue }

            let marks = result[marksRange].filter { !$0.isWhitespace }
            let strongest = strongestPunctuation(in: marks)
            result.replaceSubrange(fullRange, with: String(strongest))
        }

        // Drop a dangling separator left at the text boundaries (e.g. a table
        // row's outer pipes, now commas).
        let fullRange = NSRange(location: 0, length: result.utf16.count)
        result = leadingSeparatorRegex.stringByReplacingMatches(
            in: result, range: fullRange, withTemplate: ""
        )
        result = trailingSeparatorRegex.stringByReplacingMatches(
            in: result, range: NSRange(location: 0, length: result.utf16.count), withTemplate: ""
        )
        return result
    }

    /// Returns the strongest punctuation mark in `marks`, ordered
    /// `.!?` > `:;` > `,`. Falls back to the first mark for anything unranked.
    private static func strongestPunctuation(in marks: some Sequence<Character>) -> Character {
        func rank(_ char: Character) -> Int {
            switch char {
            case ".", "!", "?": 3
            case ":", ";": 2
            case ",": 1
            default: 0
            }
        }
        return marks.max { rank($0) < rank($1) } ?? ","
    }

    // MARK: - Number Processing

    private static let commaInNumberRegex = try! NSRegularExpression(
        pattern: #"\b(\d{1,3})(,\d{3})+\b"#
    )

    /// Remove commas from numbers: 1,000 → 1000
    private static func removeCommasFromNumbers(_ text: String) -> String {
        let matches = commaInNumberRegex.matches(
            in: text, range: NSRange(location: 0, length: text.utf16.count)
        )

        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let cleaned = result[range].replacingOccurrences(of: ",", with: "")
            result.replaceSubrange(range, with: cleaned)
        }
        return result
    }

    private static let rangeRegex = try! NSRegularExpression(
        pattern: #"([$£€]?\d+)-([$£€]?\d+)"#
    )

    /// Handle ranges: 5-10 → "5 to 10"
    private static func processRanges(_ text: String, locale: SpokenTextLocale) -> String {
        rangeRegex.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: text.utf16.count),
            withTemplate: "$1 \(locale.rangeWord) $2"
        )
    }

    // MARK: - Currency Processing

    private static let currencyRegex = try! NSRegularExpression(
        pattern: #"([$£€])\s*(\d+)(?:\.(\d{1,2}))?"#
    )

    private static func processCurrencies(_ text: String, locale: SpokenTextLocale) -> String {
        let matches = currencyRegex.matches(
            in: text, range: NSRange(location: 0, length: text.utf16.count)
        )

        var result = text
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let symbolRange = Range(match.range(at: 1), in: result),
                  let mainRange = Range(match.range(at: 2), in: result)
            else { continue }

            let symbol = result[symbolRange].first!
            guard let currency = locale.currencies[symbol],
                  let mainValue = Int(result[mainRange])
            else { continue }

            let subValue = if match.range(at: 3).location != NSNotFound,
                              let subRange = Range(match.range(at: 3), in: result)
            {
                Int(result[subRange]) ?? 0
            } else {
                0
            }

            let mainWord = locale.numberFormatter.string(from: NSNumber(
                value: mainValue
            )) ?? "\(mainValue)"
            let mainUnit = mainValue == 1 ? currency.singular : currency.plural

            let replacement: String
            if subValue == 0 {
                replacement = "\(mainWord) \(mainUnit)"
            } else {
                let subWord = locale.numberFormatter.string(from: NSNumber(
                    value: subValue
                )) ?? "\(subValue)"
                let subUnit = subValue == 1 ? currency.subSingular : currency.subPlural
                replacement = "\(mainWord) \(mainUnit) \(locale.andWord) \(subWord) \(subUnit)"
            }

            result.replaceSubrange(fullRange, with: replacement)
        }
        return result
    }

    // MARK: - Time Processing

    /// Matches both 12-hour (`1:30`) and 24-hour (`16:10`) clock times.
    /// Hours: 0–23, minutes: 00–59. Without 24-hour support, times like
    /// `16:10` slipped through and were spelled out as `seksten:ti` with a
    /// literal colon, which broke prosody for some TTS engines.
    private static let clockTimeRegex = try! NSRegularExpression(
        pattern: #"\b([01]?\d|2[0-3]):([0-5]\d)\b"#
    )

    private static func processTimes(_ text: String, locale: SpokenTextLocale) -> String {
        let matches = clockTimeRegex.matches(
            in: text, range: NSRange(location: 0, length: text.utf16.count)
        )

        var result = text
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let hourRange = Range(match.range(at: 1), in: result),
                  let minRange = Range(match.range(at: 2), in: result),
                  let hours = Int(result[hourRange]),
                  let minutes = Int(result[minRange])
            else { continue }

            let replacement = locale.formatClockTime(hours, minutes)
            result.replaceSubrange(fullRange, with: replacement)
        }
        return result
    }

    // MARK: - Decimal Numbers

    private static let decimalRegex = try! NSRegularExpression(
        pattern: #"\b\d*\.\d+(?=\s|[a-zA-Z]|[).,;:!?]|$)"#
    )

    private static func processDecimalNumbers(_ text: String, locale: SpokenTextLocale) -> String {
        let matches = decimalRegex.matches(
            in: text, range: NSRange(location: 0, length: text.utf16.count)
        )

        var result = text
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result) else { continue }

            let matchText = String(result[fullRange])
            let parts = matchText.components(separatedBy: ".")
            guard parts.count == 2 else { continue }

            let integerWord: String = if let intVal = Int(parts[0]) {
                locale.numberFormatter.string(from: NSNumber(value: intVal)) ?? parts[0]
            } else {
                parts[0]
            }

            let decimalWords = parts[1].compactMap { char -> String? in
                guard let digit = char.wholeNumberValue,
                      digit < locale.digitWords.count else { return nil }
                return locale.digitWords[digit]
            }.joined(separator: " ")

            result.replaceSubrange(
                fullRange,
                with: "\(integerWord) \(locale.pointWord) \(decimalWords)"
            )
        }
        return result
    }

    // MARK: - Ordinal Dates

    /// "9. april" → "niende april", "1. januar 2026" → "første januar 2026".
    /// Matches `<day>. <month>` where `<month>` is one of the locale's month
    /// names. Common in Danish and other European date formats. English text
    /// almost never uses this form, so the regex naturally won't fire there.
    private static func processOrdinalDates(_ text: String, locale: SpokenTextLocale) -> String {
        // Build an alternation over all month names from the locale, skipping
        // the empty placeholder at index 0.
        let monthAlternation = locale.monthNames.dropFirst()
            .filter { !$0.isEmpty }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        guard !monthAlternation.isEmpty else { return text }

        let pattern = #"\b(\d{1,2})\.\s*("# + monthAlternation + #")\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        else { return text }

        var result = text
        let matches = regex.matches(
            in: result, range: NSRange(location: 0, length: result.utf16.count)
        )
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let dayRange = Range(match.range(at: 1), in: result),
                  let monthRange = Range(match.range(at: 2), in: result),
                  let day = Int(result[dayRange]),
                  day >= 1, day <= 31
            else { continue }
            let month = String(result[monthRange])
            let ordinal = locale.ordinalWord(day)
            result.replaceSubrange(fullRange, with: "\(ordinal) \(month)")
        }
        return result
    }

    // MARK: - Alphanumeric Codes

    /// Matches uppercase-letter + digit codes, optionally hyphen-separated.
    /// `42F-17`, `B42`, `X420-MF-BST68`, `R2-D2`, etc. Lookaheads require at
    /// least one uppercase letter AND at least one digit so plain numbers
    /// (`123`), plain words (`USA`), and lowercase tokens (`wifi-2`) don't
    /// match — they have natural pronunciations the model handles fine.
    private static let alphanumericCodeRegex = try! NSRegularExpression(
        pattern: #"\b(?=[A-Z0-9-]*[A-Z])(?=[A-Z0-9-]*[0-9])[A-Z0-9-]+\b"#
    )

    /// `42F-17` → `fire to F en syv`. Each digit is spelled via the locale's
    /// `digitWords`; each letter is left as a standalone uppercase character
    /// so the TTS reads it as a letter name; hyphens become spaces. The
    /// resulting space-separated tokens give the model a clear cue to
    /// pronounce each character individually.
    private static func processAlphanumericCodes(
        _ text: String,
        locale: SpokenTextLocale
    ) -> String {
        let matches = alphanumericCodeRegex.matches(
            in: text, range: NSRange(location: 0, length: text.utf16.count)
        )
        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let code = String(result[range])
            let parts: [String] = code.compactMap { char in
                if char == "-" { return nil }
                if let digit = char.wholeNumberValue, digit < locale.digitWords.count {
                    return locale.digitWords[digit]
                }
                return String(char)
            }
            result.replaceSubrange(range, with: parts.joined(separator: " "))
        }
        return result
    }

    // MARK: - Unit Abbreviations

    private static func processUnitAbbreviations(
        _ text: String,
        locale: SpokenTextLocale
    ) -> String {
        var result = text

        for (abbrev, (singular, plural)) in locale.unitAbbreviations {
            let escaped = NSRegularExpression.escapedPattern(for: abbrev)
            let pattern = #"\b(\d+(?:\.\d+)?)\s*"# + escaped + #"\b"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }

            let matches = regex.matches(
                in: result, range: NSRange(location: 0, length: result.utf16.count)
            )

            for match in matches.reversed() {
                guard let fullRange = Range(match.range, in: result),
                      let numRange = Range(match.range(at: 1), in: result)
                else { continue }

                let numStr = String(result[numRange])
                let number = Double(numStr) ?? 1.0
                let unit = number == 1.0 ? singular : plural
                result.replaceSubrange(fullRange, with: "\(numStr) \(unit)")
            }
        }
        return result
    }

    // MARK: - Common Abbreviations

    private static func processCommonAbbreviations(
        _ text: String,
        locale: SpokenTextLocale
    ) -> String {
        var result = text

        // Process longer abbreviations first so "etc." matches before "etc".
        let sorted = locale.commonAbbreviations.sorted { $0.key.count > $1.key.count }
        for (abbrev, expansion) in sorted {
            let escaped = NSRegularExpression.escapedPattern(for: abbrev)
            // For abbreviations ending with a period, use a lookahead for
            // non-word or end-of-string instead of \b (which doesn't match
            // after a period since both sides are non-word characters).
            let trailing = abbrev.hasSuffix(".") ? "(?=\\W|$)" : #"\b"#
            let pattern = #"\b"# + escaped + trailing
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            else { continue }

            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: expansion
            )
        }
        return result
    }

    // MARK: - Whole Numbers

    private static let wholeNumberRegex = try! NSRegularExpression(pattern: #"\b\d+\b"#)

    private static func spellOutWholeNumbers(_ text: String, locale: SpokenTextLocale) -> String {
        let matches = wholeNumberRegex.matches(
            in: text, range: NSRange(location: 0, length: text.utf16.count)
        )

        var result = text
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let digits = String(result[range])
            guard let value = Int(digits),
                  let spelled = locale.numberFormatter.string(from: NSNumber(value: value))
            else { continue }
            result.replaceSubrange(range, with: spelled)
        }
        return result
    }
}
