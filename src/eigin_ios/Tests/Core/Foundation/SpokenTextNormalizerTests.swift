@testable import Eigin
import Testing

@Suite("SpokenTextNormalizer")
struct SpokenTextNormalizerTests {
    // MARK: - English

    let en = SpokenTextLocale.english()

    @Test func englishWholeNumbers() {
        #expect(SpokenTextNormalizer.normalize("I have 5 cats", locale: en) == "I have five cats")
        #expect(SpokenTextNormalizer
            .normalize("There are 100 items", locale: en) == "There are one hundred items")
        #expect(SpokenTextNormalizer.normalize("Page 42", locale: en) == "Page forty-two")
    }

    @Test func englishCommaNumbers() {
        #expect(SpokenTextNormalizer
            .normalize("Population: 1,000", locale: en) == "Population: one thousand")
        #expect(SpokenTextNormalizer
            .normalize("Cost is 1,234,567", locale: en) ==
            "Cost is one million two hundred thirty-four thousand five hundred sixty-seven")
    }

    @Test func englishDecimalNumbers() {
        #expect(SpokenTextNormalizer
            .normalize("Temperature is 3.5 degrees", locale: en) ==
            "Temperature is three point five degrees")
        #expect(SpokenTextNormalizer
            .normalize("Version 2.0 released", locale: en) == "Version two point zero released")
    }

    @Test func englishRanges() {
        #expect(SpokenTextNormalizer.normalize("Pages 5-10", locale: en) == "Pages five to ten")
        #expect(SpokenTextNormalizer
            .normalize("$50-$100", locale: en) == "fifty dollars to one hundred dollars")
    }

    @Test func englishCurrencies() {
        #expect(SpokenTextNormalizer
            .normalize("It costs $5", locale: en) == "It costs five dollars")
        #expect(SpokenTextNormalizer.normalize("Price: $1", locale: en) == "Price: one dollar")
        #expect(SpokenTextNormalizer
            .normalize("Total: $12.50", locale: en) == "Total: twelve dollars and fifty cents")
        #expect(SpokenTextNormalizer.normalize("€1.01", locale: en) == "one euro and one cent")
        #expect(SpokenTextNormalizer.normalize("£99", locale: en) == "ninety-nine pounds")
    }

    @Test func englishClockTimes() {
        #expect(SpokenTextNormalizer
            .normalize("Meet at 3:00", locale: en) == "Meet at three o'clock")
        #expect(SpokenTextNormalizer.normalize("Call at 2:30", locale: en) == "Call at two thirty")
        #expect(SpokenTextNormalizer.normalize("At 9:05", locale: en) == "At nine oh five")
    }

    @Test func englishTwentyFourHourTimes() {
        // 24-hour times must be detected as a single time, not split into two
        // independent numbers separated by a literal colon.
        let result = SpokenTextNormalizer.normalize("Meeting at 16:10.", locale: en)
        #expect(result.contains("sixteen ten"))
        #expect(!result.contains(":"))

        // Edge of 24-hour range — 23:59.
        let late = SpokenTextNormalizer.normalize("at 23:59", locale: en)
        #expect(!late.contains(":"))
        #expect(late.contains("twenty-three fifty-nine"))
    }

    @Test func englishOrdinalDates() {
        // The "<day>. <month>" form is unusual in English but should still be
        // normalized correctly when it does appear.
        let single = SpokenTextNormalizer.normalize("Meeting 9. April", locale: en)
        #expect(single.contains("ninth April"))
        #expect(!single.contains("nine April"))

        // First day uses the irregular "first" ordinal.
        let first = SpokenTextNormalizer.normalize("1. January is New Year", locale: en)
        #expect(first.contains("first January"))

        // Two-digit days work too.
        let twentyThird = SpokenTextNormalizer.normalize("23. December", locale: en)
        #expect(twentyThird.contains("twenty-third December"))

        // A standalone number followed by a period that isn't a month should
        // still be spelled as a cardinal.
        let notADate = SpokenTextNormalizer.normalize("Item 9. It is important.", locale: en)
        #expect(notADate.contains("nine"))
        #expect(!notADate.contains("ninth"))
    }

    @Test func englishAlphanumericCodes() {
        // Letter + digit codes are spelled character-by-character so the TTS
        // reads them as a code rather than mispronouncing the letter cluster.
        let single = SpokenTextNormalizer.normalize("Case 42F-17", locale: en)
        #expect(single.contains("four two F one seven"))
        #expect(!single.contains("42F-17"))

        // Address-style code with leading uppercase letter.
        let address = SpokenTextNormalizer.normalize("Apartment B42", locale: en)
        #expect(address.contains("B four two"))

        // Multi-segment code with hyphens.
        let part = SpokenTextNormalizer.normalize("Part X420-MF-BST68", locale: en)
        #expect(part.contains("X four two zero M F B S T six eight"))

        // Plain all-letter words should be left alone.
        let plain = SpokenTextNormalizer.normalize("USA has 50 states", locale: en)
        #expect(plain.contains("USA"))

        // Lowercase code-like tokens should not be touched.
        let lowercaseHybrid = SpokenTextNormalizer.normalize("Use wifi-2 here", locale: en)
        #expect(lowercaseHybrid.contains("wifi"))
    }

    @Test func englishUnits() {
        #expect(SpokenTextNormalizer.normalize("5kg", locale: en) == "five kilograms")
        #expect(SpokenTextNormalizer.normalize("1kg", locale: en) == "one kilogram")
        #expect(SpokenTextNormalizer
            .normalize("100ml of water", locale: en) == "one hundred milliliters of water")
        #expect(SpokenTextNormalizer.normalize("2km away", locale: en) == "two kilometers away")
    }

    @Test func englishAbbreviations() {
        #expect(SpokenTextNormalizer
            .normalize("Dr. Smith vs Mr. Jones", locale: en) == "Doctor Smith versus Mister Jones")
        // "etc." at end of sentence: the abbreviation period is consumed by the pattern,
        // but the sentence-ending period from the original is separate.
        #expect(SpokenTextNormalizer
            .normalize("See notes, etc. here", locale: en) == "See notes, etcetera here")
    }

    @Test func englishDataUnits() {
        let gb = SpokenTextNormalizer.normalize("1.1GB", locale: en)
        #expect(gb.contains("one point one gigabytes"))

        let mb = SpokenTextNormalizer.normalize("20-30MB delta", locale: en)
        #expect(mb.contains("megabytes"))
        #expect(mb.contains("to"))

        let ms = SpokenTextNormalizer.normalize("it runs at ~400ms per step", locale: en)
        #expect(ms.contains("approximately"))
        #expect(ms.contains("four hundred milliseconds"))
    }

    @Test func englishSymbolReplacement() {
        // Slashes become spaces
        let slash = SpokenTextNormalizer.normalize("maderix/ANE", locale: en)
        #expect(!slash.contains("/"))
        #expect(slash.contains("maderix"))
        #expect(slash.contains("ANE"))

        // Parentheses become pauses, content preserved
        let parens = SpokenTextNormalizer.normalize(
            "On-device training (the holy grail)",
            locale: en
        )
        #expect(!parens.contains("("))
        #expect(parens.contains("holy grail"))

        // Tildes become "approximately"
        let tilde = SpokenTextNormalizer.normalize("~5 items", locale: en)
        #expect(tilde.contains("approximately"))
    }

    @Test func englishVersionNumbers() {
        let semver = SpokenTextNormalizer.normalize("Version 1.3.5 released", locale: en)
        #expect(semver.contains("one point three point five"))
        #expect(!semver.contains("1.3.5"))

        let prefixed = SpokenTextNormalizer.normalize("Running v2.0.1", locale: en)
        #expect(prefixed.contains("v two point zero point one"))
    }

    @Test func englishScaleAbbreviations() {
        let params = SpokenTextNormalizer.normalize("100M parameters", locale: en)
        #expect(params.contains("one hundred million parameters"))

        let big = SpokenTextNormalizer.normalize("1.5B tokens", locale: en)
        #expect(big.contains("one point five billion tokens"))

        let small = SpokenTextNormalizer.normalize("7B model", locale: en)
        #expect(small.contains("seven billion model"))
    }

    @Test func englishURLsAndDomains() {
        // Bare domain
        let bare = SpokenTextNormalizer.normalize("Check github.com for details", locale: en)
        #expect(bare.contains("github dot com"))
        #expect(!bare.contains("github.com"))

        // Full URL — reduced to domain
        let full = SpokenTextNormalizer.normalize(
            "Visit https://google.com/search?q=test",
            locale: en
        )
        #expect(full.contains("google dot com"))
        #expect(!full.contains("https"))
        #expect(!full.contains("search"))

        // www prefix
        let www = SpokenTextNormalizer.normalize("Go to www.site.com", locale: en)
        #expect(www.contains("w w w dot site dot com"))

        // Subdomain
        let sub = SpokenTextNormalizer.normalize("See docs.example.io", locale: en)
        #expect(sub.contains("docs dot example dot io"))
    }

    @Test func englishPassthrough() {
        #expect(SpokenTextNormalizer.normalize("Hello world", locale: en) == "Hello world")
        #expect(SpokenTextNormalizer.normalize("", locale: en) == "")
    }

    // MARK: - Danish

    let da = SpokenTextLocale.danish()

    @Test func danishWholeNumbers() {
        let result = SpokenTextNormalizer.normalize("Jeg har 5 katte", locale: da)
        #expect(result == "Jeg har fem katte")
    }

    @Test func danishCommaNumbers() {
        let result = SpokenTextNormalizer.normalize("Befolkning: 1,000", locale: da)
        #expect(result.contains("tusind") || result.contains("tusinde"))
    }

    @Test func danishDecimalNumbers() {
        let result = SpokenTextNormalizer.normalize("Temperatur er 3.5 grader", locale: da)
        #expect(result.contains("komma"))
    }

    @Test func danishRanges() {
        let result = SpokenTextNormalizer.normalize("Side 5-10", locale: da)
        #expect(result.contains("til"))
    }

    @Test func danishCurrencies() {
        let result = SpokenTextNormalizer.normalize("Det koster $5", locale: da)
        #expect(result.contains("dollar"))
    }

    @Test func danishClockTimes() {
        let result = SpokenTextNormalizer.normalize("Mødes kl 3:00", locale: da)
        #expect(result.contains("tre"))
    }

    @Test func danishTwentyFourHourTimes() {
        // 24-hour times must be detected as a single time, not split into two
        // independent numbers separated by a literal colon (which trips up
        // some TTS models and can drop the trailing token).
        let result = SpokenTextNormalizer.normalize("Mødet er kl. 16:10.", locale: da)
        #expect(result.contains("seksten"))
        #expect(result.contains("ti"))
        #expect(!result.contains(":"))
        #expect(result.contains("klokken"))

        // Edge of 24-hour range — 23:59.
        let late = SpokenTextNormalizer.normalize("kl. 23:59", locale: da)
        #expect(!late.contains(":"))
    }

    @Test func danishUnits() {
        let result = SpokenTextNormalizer.normalize("5kg", locale: da)
        #expect(result.contains("kilogram"))
    }

    @Test func danishAbbreviations() {
        let result = SpokenTextNormalizer.normalize("Dr. Hansen osv. her", locale: da)
        #expect(result.contains("Doktor"))
        #expect(result.contains("og så videre"))
    }

    @Test func danishAlphanumericCodes() {
        // Letter + digit codes are spelled character-by-character so the TTS
        // reads them as a code rather than mispronouncing the letter cluster.
        let single = SpokenTextNormalizer.normalize("Sagsnummer 42F-17", locale: da)
        #expect(single.contains("fire to F en syv"))
        #expect(!single.contains("42F-17"))

        // Address-style code with leading uppercase letter.
        let address = SpokenTextNormalizer.normalize("Bo i B42", locale: da)
        #expect(address.contains("B fire to"))

        // Multi-segment code with hyphens.
        let part = SpokenTextNormalizer.normalize("Reservedel X420-MF-BST68", locale: da)
        #expect(part.contains("X fire to nul M F B S T seks otte"))

        // Plain words and plain numbers should be unaffected.
        let plain = SpokenTextNormalizer.normalize("USA har 50 stater", locale: da)
        #expect(plain.contains("USA"))
        // Lowercase code-like tokens should not be touched.
        let lowercaseHybrid = SpokenTextNormalizer.normalize("Brug wifi-2 her", locale: da)
        #expect(lowercaseHybrid.contains("wifi"))
    }

    @Test func danishOrdinalDates() {
        // Day + month should be spoken as ordinal + month, not cardinal + month.
        let single = SpokenTextNormalizer.normalize("Mødet er 9. april", locale: da)
        #expect(single.contains("niende april"))
        #expect(!single.contains("ni april"))

        // First day of the month uses the irregular ordinal "første".
        let first = SpokenTextNormalizer.normalize("1. januar er nytår", locale: da)
        #expect(first.contains("første januar"))

        // Two-digit days work too.
        let twentyThird = SpokenTextNormalizer.normalize("23. december", locale: da)
        #expect(twentyThird.contains("december"))
        #expect(!twentyThird.contains("23 december"))

        // A standalone number followed by a period that isn't a month should
        // still be spelled as a cardinal — not the ordinal "niende".
        let notADate = SpokenTextNormalizer.normalize("Punkt 9. Det er vigtigt.", locale: da)
        #expect(notADate.contains("ni"))
        #expect(!notADate.contains("niende"))
    }

    @Test func danishPassthrough() {
        #expect(SpokenTextNormalizer.normalize("Hej verden", locale: da) == "Hej verden")
    }
}
