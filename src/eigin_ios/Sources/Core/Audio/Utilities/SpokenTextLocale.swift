import Foundation

/// Language-specific rules for converting written text into spoken form.
///
/// Each locale provides the data and logic needed by ``SpokenTextNormalizer``
/// to transform numbers, dates, currencies, units, and abbreviations into
/// words that a TTS engine can pronounce naturally.
struct SpokenTextLocale: @unchecked Sendable {
    let identifier: String
    let numberFormatter: NumberFormatter
    let monthNames: [String] // 13 elements, index 0 empty for 1-based indexing
    let ordinalWord: @Sendable (Int) -> String
    let formatYear: @Sendable (Int) -> String
    let formatClockTime: @Sendable (Int, Int) -> String
    let currencies:
        [Character: (singular: String, plural: String, subSingular: String, subPlural: String)]
    let unitAbbreviations: [String: (singular: String, plural: String)]
    let commonAbbreviations: [String: String]
    let rangeWord: String
    let pointWord: String
    let dotWord: String // "dot" for domains/URLs
    let approximatelyWord: String
    let oClockPhrase: @Sendable (String) -> String // takes spelled hour, returns "X o'clock" etc.
    let andWord: String
    let digitWords: [String] // "zero" through "nine"
    let scaleWords: [String: String] // "K" → "thousand", "M" → "million", etc.
    let durationMinuteWord: (singular: String, plural: String)
    let durationSecondWord: (singular: String, plural: String)
    let fractionHalf: (singular: String, plural: String)
    let fractionQuarter: (singular: String, plural: String)
}

// MARK: - English

extension SpokenTextLocale {
    static func english() -> SpokenTextLocale {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en_US_POSIX")

        return SpokenTextLocale(
            identifier: "en",
            numberFormatter: formatter,
            monthNames: [
                "", "January", "February", "March", "April", "May", "June",
                "July", "August", "September", "October", "November", "December",
            ],
            ordinalWord: englishOrdinalWord,
            formatYear: { year in englishFormatYear(year, formatter: formatter) },
            formatClockTime: { hours, minutes in
                let hourWord = formatter.string(from: NSNumber(value: hours)) ?? "\(hours)"
                if minutes == 0 {
                    return "\(hourWord) o'clock"
                } else if minutes >= 1, minutes <= 9 {
                    let minWord = formatter.string(from: NSNumber(value: minutes)) ?? "\(minutes)"
                    return "\(hourWord) oh \(minWord)"
                } else {
                    let minWord = formatter.string(from: NSNumber(value: minutes)) ?? "\(minutes)"
                    return "\(hourWord) \(minWord)"
                }
            },
            currencies: [
                "$": ("dollar", "dollars", "cent", "cents"),
                "£": ("pound", "pounds", "pence", "pence"),
                "€": ("euro", "euros", "cent", "cents"),
            ],
            unitAbbreviations: englishUnits,
            commonAbbreviations: [
                "vs": "versus", "vs.": "versus",
                "etc": "etcetera", "etc.": "etcetera",
                "e.g.": "for example", "i.e.": "that is",
                "Mr.": "Mister", "Mrs.": "Missus", "Ms.": "Miss",
                "Dr.": "Doctor", "Prof.": "Professor", "St.": "Saint",
            ],
            rangeWord: "to",
            pointWord: "point",
            dotWord: "dot",
            approximatelyWord: "approximately",
            oClockPhrase: { hourWord in "\(hourWord) o'clock" },
            andWord: "and",
            digitWords: [
                "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
            ],
            scaleWords: ["K": "thousand", "M": "million", "B": "billion", "T": "trillion"],
            durationMinuteWord: ("minute", "minutes"),
            durationSecondWord: ("second", "seconds"),
            fractionHalf: ("half", "halves"),
            fractionQuarter: ("quarter", "quarters")
        )
    }

    // MARK: English Ordinals

    private static let englishOrdinalWords: [Int: String] = [
        1: "first", 2: "second", 3: "third", 4: "fourth", 5: "fifth",
        6: "sixth", 7: "seventh", 8: "eighth", 9: "ninth", 10: "tenth",
        11: "eleventh", 12: "twelfth", 13: "thirteenth", 14: "fourteenth", 15: "fifteenth",
        16: "sixteenth", 17: "seventeenth", 18: "eighteenth", 19: "nineteenth",
    ]

    private static func englishOrdinalWord(_ number: Int) -> String {
        if let cached = englishOrdinalWords[number] { return cached }

        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "en_US_POSIX")
        guard let spelled = formatter.string(from: NSNumber(value: number)) else {
            return "\(number)th"
        }

        return englishAddOrdinalSuffix(to: spelled, number: number)
    }

    private static func englishAddOrdinalSuffix(to spelled: String, number: Int) -> String {
        let lastDigit = number % 10
        let lastTwoDigits = number % 100

        if lastTwoDigits >= 11, lastTwoDigits <= 13 {
            if spelled.hasSuffix("one") { return String(spelled.dropLast(3)) + "eleventh" }
            if spelled.hasSuffix("two") { return String(spelled.dropLast(3)) + "twelfth" }
            if spelled.hasSuffix("three") { return String(spelled.dropLast(5)) + "thirteenth" }
        }

        switch lastDigit {
        case 1 where spelled.hasSuffix("one"): return String(spelled.dropLast(3)) + "first"
        case 2 where spelled.hasSuffix("two"): return String(spelled.dropLast(3)) + "second"
        case 3 where spelled.hasSuffix("three"): return String(spelled.dropLast(5)) + "third"
        case 5 where spelled.hasSuffix("five"): return String(spelled.dropLast(4)) + "fifth"
        case 8 where spelled.hasSuffix("eight"): return String(spelled.dropLast(5)) + "eighth"
        case 9 where spelled.hasSuffix("nine"): return String(spelled.dropLast(4)) + "ninth"
        case 0 where spelled.hasSuffix("y"): return String(spelled.dropLast(1)) + "ieth"
        default: return spelled + "th"
        }
    }

    // MARK: English Year Formatting

    private static func englishFormatYear(_ year: Int, formatter: NumberFormatter) -> String {
        guard year >= 1000, year <= 9999 else {
            return formatter.string(from: NSNumber(value: year)) ?? "\(year)"
        }

        let century = year / 100
        let remainder = year % 100
        let centuryWord = formatter.string(from: NSNumber(value: century)) ?? "\(century)"

        if remainder == 0 {
            return year == 2000 ? "two thousand" : "\(centuryWord) hundred"
        } else if year >= 2000, year <= 2009 {
            let remWord = formatter.string(from: NSNumber(value: remainder)) ?? "\(remainder)"
            return "two thousand \(remWord)"
        } else if remainder >= 1, remainder <= 9 {
            let remWord = formatter.string(from: NSNumber(value: remainder)) ?? "\(remainder)"
            return "\(centuryWord) oh \(remWord)"
        } else {
            let remWord = formatter.string(from: NSNumber(value: remainder)) ?? "\(remainder)"
            return "\(centuryWord) \(remWord)"
        }
    }

    // MARK: English Units

    private static let englishUnits: [String: (singular: String, plural: String)] = [
        // Weight
        "g": ("gram", "grams"), "kg": ("kilogram", "kilograms"),
        "mg": ("milligram", "milligrams"), "lb": ("pound", "pounds"),
        "lbs": ("pounds", "pounds"), "oz": ("ounce", "ounces"),
        // Volume
        "ml": ("milliliter", "milliliters"), "l": ("liter", "liters"),
        "cl": ("centiliter", "centiliters"), "dl": ("deciliter", "deciliters"),
        "gal": ("gallon", "gallons"), "pt": ("pint", "pints"),
        "qt": ("quart", "quarts"), "tsp": ("teaspoon", "teaspoons"),
        "tbsp": ("tablespoon", "tablespoons"),
        // Length
        "mm": ("millimeter", "millimeters"), "cm": ("centimeter", "centimeters"),
        "m": ("meter", "meters"), "km": ("kilometer", "kilometers"),
        "ft": ("foot", "feet"), "yd": ("yard", "yards"), "mi": ("mile", "miles"),
        // Data storage
        "KB": ("kilobyte", "kilobytes"), "MB": ("megabyte", "megabytes"),
        "GB": ("gigabyte", "gigabytes"), "TB": ("terabyte", "terabytes"),
        "PB": ("petabyte", "petabytes"),
        // Temperature
        "°C": ("degree Celsius", "degrees Celsius"),
        "°F": ("degree Fahrenheit", "degrees Fahrenheit"),
        // Time
        "ms": ("millisecond", "milliseconds"),
        "s": ("second", "seconds"), "sec": ("second", "seconds"),
        "min": ("minute", "minutes"), "hr": ("hour", "hours"), "h": ("hour", "hours"),
    ]
}

// MARK: - Danish

extension SpokenTextLocale {
    static func danish() -> SpokenTextLocale {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "da_DK")

        return SpokenTextLocale(
            identifier: "da",
            numberFormatter: formatter,
            monthNames: [
                "", "januar", "februar", "marts", "april", "maj", "juni",
                "juli", "august", "september", "oktober", "november", "december",
            ],
            ordinalWord: danishOrdinalWord,
            formatYear: { year in danishFormatYear(year, formatter: formatter) },
            formatClockTime: { hours, minutes in
                let hourWord = formatter.string(from: NSNumber(value: hours)) ?? "\(hours)"
                if minutes == 0 {
                    return hourWord
                } else {
                    let minWord = formatter.string(from: NSNumber(value: minutes)) ?? "\(minutes)"
                    return "\(hourWord) \(minWord)"
                }
            },
            currencies: [
                "$": ("dollar", "dollars", "cent", "cents"),
                "£": ("pund", "pund", "pence", "pence"),
                "€": ("euro", "euro", "cent", "cent"),
                "k": ("krone", "kroner", "øre", "øre"),
            ],
            unitAbbreviations: danishUnits,
            commonAbbreviations: [
                "vs": "versus",
                "vs.": "versus",
                "osv.": "og så videre",
                "osv": "og så videre",
                "etc": "et cetera",
                "etc.": "et cetera",
                "f.eks.": "for eksempel",
                "fx": "for eksempel",
                "dvs.": "det vil sige",
                "d.v.s.": "det vil sige",
                "ol.": "og lignende",
                "o.l.": "og lignende",
                "t.d.": "til dato",
                "pr.": "per",
                "evt.": "eventuelt",
                "ift.": "i forhold til",
                "i.f.t.": "i forhold til",
                "pga.": "på grund af",
                "vha.": "ved hjælp af",
                "vedr.": "vedrørende",
                "stk.": "styk",
                "jvf": "jævnfør",
                "Mr.": "Mister",
                "Mrs.": "Fru",
                "Ms.": "Frøken",
                "Dr.": "Doktor",
                "Prof.": "Professor",
                "St.": "Sankt",
                "nr.": "nummer",
                "ca.": "cirka",
                "kl.": "klokken",
            ],
            rangeWord: "til",
            pointWord: "komma",
            dotWord: "punkt",
            approximatelyWord: "cirka",
            oClockPhrase: { hourWord in hourWord },
            andWord: "og",
            digitWords: ["nul", "en", "to", "tre", "fire", "fem", "seks", "syv", "otte", "ni"],
            scaleWords: ["K": "tusind", "M": "millioner", "B": "milliarder", "T": "billioner"],
            durationMinuteWord: ("minut", "minutter"),
            durationSecondWord: ("sekund", "sekunder"),
            fractionHalf: ("halv", "halve"),
            fractionQuarter: ("kvart", "kvarte")
        )
    }

    // MARK: Danish Ordinals

    private static let danishOrdinalWords: [Int: String] = [
        1: "første", 2: "anden", 3: "tredje", 4: "fjerde", 5: "femte",
        6: "sjette", 7: "syvende", 8: "ottende", 9: "niende", 10: "tiende",
        11: "ellevte", 12: "tolvte", 13: "trettende", 14: "fjortende", 15: "femtende",
        16: "sekstende", 17: "syttende", 18: "attende", 19: "nittende",
        20: "tyvende",
    ]

    private static func danishOrdinalWord(_ number: Int) -> String {
        if let cached = danishOrdinalWords[number] { return cached }

        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        formatter.locale = Locale(identifier: "da_DK")
        guard let spelled = formatter.string(from: NSNumber(value: number)) else {
            return "\(number)."
        }

        // Danish ordinals generally add -de or -te to the cardinal form
        if spelled.hasSuffix("e") {
            return spelled + "nde"
        }
        return spelled + "de"
    }

    // MARK: Danish Year Formatting

    private static func danishFormatYear(_ year: Int, formatter: NumberFormatter) -> String {
        // Danish typically just spells out the full number for years
        formatter.string(from: NSNumber(value: year)) ?? "\(year)"
    }

    // MARK: Danish Units

    private static let danishUnits: [String: (singular: String, plural: String)] = [
        // Weight
        "g": ("gram", "gram"),
        "kg": ("kilogram", "kilogram"),
        "mg": ("milligram", "milligram"),
        "lb": ("pund", "pund"),
        "lbs": ("pund", "pund"),
        "oz": ("ounce", "ounces"),
        // Volume
        "ml": ("milliliter", "milliliter"),
        "l": ("liter", "liter"),
        "cl": ("centiliter", "centiliter"),
        "dl": ("deciliter", "deciliter"),
        // Length
        "mm": ("millimeter", "millimeter"),
        "cm": ("centimeter", "centimeter"),
        "m": ("meter", "meter"),
        "km": ("kilometer", "kilometer"),
        // Data storage
        "KB": ("kilobyte", "kilobytes"),
        "MB": ("megabyte", "megabytes"),
        "GB": ("gigabyte", "gigabytes"),
        "TB": ("terabyte", "terabytes"),
        "PB": ("petabyte", "petabytes"),
        // Temperature
        "°C": ("grad Celsius", "grader Celsius"),
        "°F": ("grad Fahrenheit", "grader Fahrenheit"),
        // Time
        "ms": ("millisekund", "millisekunder"),
        "s": ("sekund", "sekunder"),
        "sec": ("sekund", "sekunder"),
        "min": ("minut", "minutter"),
        "hr": ("time", "timer"),
        "h": ("time", "timer"),
    ]
}

// MARK: - AppLanguage Integration

extension SpokenTextLocale {
    static func forLanguage(_ language: AppLanguage) -> SpokenTextLocale {
        switch language {
        case .english: .english()
        case .danish: .danish()
        }
    }
}
