//! Curated site focuses for the search endpoint.
//!
//! A named site focus lets a caller narrow results to a curated domain list
//! instead of naming individual domains.

/// Staan's `include_domains` hard-rejects more than 10 domains with a 400.
/// The curated lists are pruned to stay under this, but the cap is enforced
/// again at call time so a future list edit can't break the endpoint.
pub(crate) const MAX_INCLUDE_DOMAINS: usize = 10;

/// A named site focus a caller can ask for instead of naming individual domains.
///
/// Kept as a closed set of server-known categories, rather than an arbitrary
/// domain list, so the model-facing tool surface stays a single simple enum.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SearchFocus {
    /// Restrict results to a curated list of trusted recipe sites.
    Recipes,
    /// Restrict results to a curated list of trusted book sites.
    Books,
    /// Restrict results to a curated list of trusted game sites.
    Games,
    /// Restrict results to a curated list of trusted music sites.
    Music,
}

impl SearchFocus {
    /// Parses a focus value from the client-supplied query string, if recognised.
    ///
    /// Unrecognised values are ignored rather than rejected, since a new or
    /// mistyped focus should degrade to an unfiltered search, not a hard error.
    pub fn parse(value: Option<&str>) -> Option<Self> {
        match value {
            Some("recipes") => Some(Self::Recipes),
            Some("books") => Some(Self::Books),
            Some("games") => Some(Self::Games),
            Some("music") => Some(Self::Music),
            _ => None,
        }
    }

    pub(super) fn domains(self) -> &'static [&'static str] {
        match self {
            Self::Recipes => RECIPE_DOMAINS,
            Self::Books => BOOK_DOMAINS,
            Self::Games => GAME_DOMAINS,
            Self::Music => MUSIC_DOMAINS,
        }
    }
}

/// Curated domains used to narrow results when [`SearchFocus::Recipes`] is requested.
///
/// A mix of well-established Nordic recipe sites (first, matching the household
/// context the cooking skill is built around) and global flagships, chosen so the
/// list fits Staan's 10-domain `include_domains` cap.
///
/// Excludes sites whose `robots.txt` disallows AI user agents (e.g.
/// `ChatGPT-User`, `Claude-Web`/`Claude-User`, `Perplexity-User`,
/// `MistralAI-User`).
const RECIPE_DOMAINS: &[&str] = &[
    // Nordic / North European
    "valdemarsro.dk",
    "arla.dk",
    "coop.dk",
    "matprat.no",
    "ica.se",
    "koket.se",
    "lecker.de",
    "ah.nl",
    // Global
    "bbcgoodfood.com",
    "jamieoliver.com",
];

/// Curated domains used to narrow results when [`SearchFocus::Books`] is requested.
///
/// Same selection as [`RECIPE_DOMAINS`]: Nordic-first, capped at 10, no site whose
/// `robots.txt` disallows AI user agents.
const BOOK_DOMAINS: &[&str] = &[
    // Nordic / North European
    "litteratursiden.dk",
    "bibliotek.dk",
    "saxo.com",
    "plusbog.dk",
    "bokelskere.no",
    "dagensbok.com",
    "perlentaucher.de",
    "kirjasampo.fi",
    // Global
    "goodreads.com",
    "thestorygraph.com",
];

/// Curated domains used to narrow results when [`SearchFocus::Games`] is requested.
///
/// Same selection as [`RECIPE_DOMAINS`]. Many gaming outlets (IGN, Eurogamer,
/// Rock Paper Shotgun, Polygon, Kotaku, VG247, TheGamer, HowLongToBeat) block
/// real-time AI user agents outright and were dropped; Nordic coverage is one
/// verified, unrestricted flagship site per country.
const GAME_DOMAINS: &[&str] = &[
    // Nordic / North European
    "gamer.no",
    "fragbite.se",
    "pelit.fi",
    "spiluniverset.dk",
    // Global
    "gamespot.com",
    "metacritic.com",
    "opencritic.com",
    "store.steampowered.com",
    "mobygames.com",
    "giantbomb.com",
];

/// Curated domains used to narrow results when [`SearchFocus::Music`] is requested.
///
/// Same selection as [`RECIPE_DOMAINS`]. Several major music outlets (Pitchfork,
/// Rolling Stone, NME, Genius, RateYourMusic, SoundCloud, Resident Advisor,
/// Consequence) block real-time AI user agents and were dropped.
const MUSIC_DOMAINS: &[&str] = &[
    // Nordic / North European
    "gaffa.dk",
    "gaffa.no",
    "soundvenue.com",
    "rumba.fi",
    "nyafabriken.se",
    // Global
    "allmusic.com",
    "bandcamp.com",
    "stereogum.com",
    "last.fm",
    "musicbrainz.org",
];

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_recognised_focus() {
        for (value, expected) in [
            ("recipes", SearchFocus::Recipes),
            ("books", SearchFocus::Books),
            ("games", SearchFocus::Games),
            ("music", SearchFocus::Music),
        ] {
            assert_eq!(SearchFocus::parse(Some(value)), Some(expected));
        }
    }

    #[test]
    fn ignores_unrecognised_focus() {
        assert_eq!(SearchFocus::parse(Some("bogus")), None);
        assert_eq!(SearchFocus::parse(None), None);
    }

    #[test]
    fn focus_domain_lists_fit_staan_cap() {
        for focus in [
            SearchFocus::Recipes,
            SearchFocus::Books,
            SearchFocus::Games,
            SearchFocus::Music,
        ] {
            assert!(
                focus.domains().len() <= MAX_INCLUDE_DOMAINS,
                "{focus:?} lists {} domains; Staan rejects more than {MAX_INCLUDE_DOMAINS}",
                focus.domains().len()
            );
        }
    }
}
