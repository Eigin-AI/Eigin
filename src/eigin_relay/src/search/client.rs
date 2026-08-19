//! Abstraction for the upstream search API client.
//!
//! Provides a trait-based interface for making search requests, allowing
//! different implementations (real HTTP client, mock for tests).

use async_trait::async_trait;
use reqwest::Client;

/// Result type returned by search operations.
pub type SearchResult = Vec<u8>;

/// Curated domains used to narrow results when [`SearchFocus::Recipes`] is requested.
///
/// A mix of well-established global recipe sites and North European
/// ones, matching the household context the cooking skill is built around.
/// Mojeek's `fi` param accepts at most 25 domains — stay well under that.
///
/// Excludes sites whose `robots.txt` disallows AI user agents (e.g.
/// `ChatGPT-User`, `Claude-Web`/`Claude-User`, `Perplexity-User`,
/// `MistralAI-User`).
const RECIPE_DOMAINS: &[&str] = &[
    // Global
    "bbcgoodfood.com",
    "jamieoliver.com",
    "thekitchn.com",
    "natashaskitchen.com",
    "budgetbytes.com",
    "kingarthurbaking.com",
    "delish.com",
    "thepioneerwoman.com",
    "onceuponachef.com",
    "loveandlemons.com",
    // Nordic / North European
    "valdemarsro.dk",
    "coop.dk",
    "arla.dk",
    "koket.se",
    "ica.se",
    "lecker.de",
    "kotikokki.net",
    "matprat.no",
    "valio.fi",
    "ah.nl",
];

/// Curated domains used to narrow results when [`SearchFocus::Books`] is requested.
///
/// Same exclusion criteria as [`RECIPE_DOMAINS`]: no site whose `robots.txt`
/// disallows AI user agents (e.g. `ChatGPT-User`, `Claude-Web`/`Claude-User`,
/// `Perplexity-User`, `MistralAI-User`).
const BOOK_DOMAINS: &[&str] = &[
    // Global
    "goodreads.com",
    "thestorygraph.com",
    "bookriot.com",
    "lithub.com",
    "librarything.com",
    "kirkusreviews.com",
    "electricliterature.com",
    "penguin.co.uk",
    // Nordic / North European
    "litteratursiden.dk",
    "bibliotek.dk",
    "saxo.com",
    "plusbog.dk",
    "bokelskere.no",
    "dagensbok.com",
    "perlentaucher.de",
    "kirjasampo.fi",
];

/// Curated domains used to narrow results when [`SearchFocus::Games`] is requested.
///
/// Same exclusion criteria as [`RECIPE_DOMAINS`]. Many gaming outlets (IGN, Eurogamer,
/// Rock Paper Shotgun, Polygon, Kotaku, VG247, TheGamer, HowLongToBeat) now block
/// real-time AI user agents outright, or block crawling broadly enough that AI
/// user agents fall through the default rule — those were dropped. Nordic coverage
/// is thinner here than recipes/books: one verified, unrestricted flagship site per
/// country rather than a full spread.
const GAME_DOMAINS: &[&str] = &[
    // Global
    "gamespot.com",
    "metacritic.com",
    "opencritic.com",
    "store.steampowered.com",
    "pcgamesn.com",
    "gamesradar.com",
    "giantbomb.com",
    "mobygames.com",
    "nintendo.com",
    "speedrun.com",
    // Nordic / North European
    "gamer.no",
    "fragbite.se",
    "pelit.fi",
    "spiluniverset.dk",
];

/// Curated domains used to narrow results when [`SearchFocus::Music`] is requested.
///
/// Same exclusion criteria as [`RECIPE_DOMAINS`]. Several major music outlets
/// (Pitchfork, Rolling Stone, NME, Genius, RateYourMusic, SoundCloud, Resident
/// Advisor, Consequence) now block real-time AI user agents and were dropped.
const MUSIC_DOMAINS: &[&str] = &[
    // Global
    "allmusic.com",
    "bandcamp.com",
    "stereogum.com",
    "last.fm",
    "musicbrainz.org",
    "loudwire.com",
    "kexp.org",
    "udiscovermusic.com",
    // Nordic / North European
    "gaffa.dk",
    "gaffa.no",
    "soundvenue.com",
    "rumba.fi",
    "nyafabriken.se",
];

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

    fn domains(self) -> &'static [&'static str] {
        match self {
            Self::Recipes => RECIPE_DOMAINS,
            Self::Books => BOOK_DOMAINS,
            Self::Games => GAME_DOMAINS,
            Self::Music => MUSIC_DOMAINS,
        }
    }
}

/// Tuning applied to an upstream search, beyond the bare query string.
#[derive(Debug, Clone, Default)]
pub struct SearchOptions {
    /// ISO 3166-1 alpha-2 region code used to boost regionally relevant results.
    pub region: Option<String>,
    /// A named site focus, mapped server-side to a curated domain list.
    pub focus: Option<SearchFocus>,
}

impl SearchOptions {
    /// Parses options from client-supplied query string values.
    ///
    /// A region is only accepted when it looks like a two-letter code — anything
    /// else is dropped rather than forwarded upstream unchecked.
    pub fn parse(region: Option<&str>, focus: Option<&str>) -> Self {
        let region = region
            .map(str::trim)
            .filter(|r| r.len() == 2 && r.chars().all(|c| c.is_ascii_alphabetic()))
            .map(str::to_ascii_uppercase);

        Self {
            region,
            focus: SearchFocus::parse(focus),
        }
    }
}

/// Trait for making search requests to an upstream API.
///
/// Implement this trait to provide custom search backends or mocks.
#[async_trait]
pub trait SearchClient: Send + Sync {
    /// Performs a search query.
    ///
    /// - `api_key`: API key for the upstream service.
    /// - `query`: The search query string.
    /// - `options`: Region/focus tuning applied on top of the bare query.
    ///
    /// Returns the raw response body bytes on success.
    async fn search(
        &self,
        api_key: &str,
        query: &str,
        options: &SearchOptions,
    ) -> Result<SearchResult, crate::AppError>;
}

/// Production implementation using reqwest.
pub struct ReqwestClient {
    client: Client,
    base_url: String,
}

impl ReqwestClient {
    /// Creates a new reqwest-based search client.
    pub fn new(client: Client, base_url: String) -> Self {
        Self { client, base_url }
    }
}

#[async_trait]
impl SearchClient for ReqwestClient {
    async fn search(
        &self,
        api_key: &str,
        query: &str,
        options: &SearchOptions,
    ) -> Result<SearchResult, crate::AppError> {
        let mut url = format!(
            "{}/search?api_key={}&q={}&fmt=json&safe=1&t=8&dlen=200&tlen=80",
            self.base_url,
            api_key,
            urlencoding::encode(query)
        );

        // Result count and snippet/title length are fixed above rather than
        // client-controlled, so no caller can inflate the cost of a search
        // against the shared community quota.

        if let Some(region) = &options.region {
            url.push_str(&format!("&rb={}&rbb=50", urlencoding::encode(region)));
        }

        if let Some(focus) = options.focus {
            let domains = focus.domains().join(",");
            url.push_str(&format!("&fi={}", urlencoding::encode(&domains)));
        }

        let response = self
            .client
            .get(&url)
            .send()
            .await
            // Strip the URL: it carries the search query, which we never log.
            .map_err(|e| crate::AppError::Upstream(e.without_url().to_string()))?;

        if !response.status().is_success() {
            return Err(crate::AppError::Upstream(format!(
                "search API returned {}",
                response.status()
            )));
        }

        let body = response
            .bytes()
            .await
            .map_err(|e| crate::AppError::Upstream(e.without_url().to_string()))?;

        Ok(body.to_vec())
    }
}

/// Creates a new production search client.
pub fn create_client(client: Client, base_url: &str) -> std::sync::Arc<dyn SearchClient> {
    std::sync::Arc::new(ReqwestClient::new(client, base_url.to_string()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_recognised_focus() {
        assert_eq!(
            SearchFocus::parse(Some("recipes")),
            Some(SearchFocus::Recipes)
        );
    }

    #[test]
    fn parses_books_focus() {
        assert_eq!(SearchFocus::parse(Some("books")), Some(SearchFocus::Books));
    }

    #[test]
    fn parses_games_focus() {
        assert_eq!(SearchFocus::parse(Some("games")), Some(SearchFocus::Games));
    }

    #[test]
    fn parses_music_focus() {
        assert_eq!(SearchFocus::parse(Some("music")), Some(SearchFocus::Music));
    }

    #[test]
    fn ignores_unrecognised_focus() {
        assert_eq!(SearchFocus::parse(Some("bogus")), None);
        assert_eq!(SearchFocus::parse(None), None);
    }

    #[test]
    fn accepts_valid_region_code() {
        let options = SearchOptions::parse(Some("dk"), None);
        assert_eq!(options.region.as_deref(), Some("DK"));
    }

    #[test]
    fn drops_malformed_region_code() {
        assert_eq!(SearchOptions::parse(Some("denmark"), None).region, None);
        assert_eq!(SearchOptions::parse(Some(""), None).region, None);
        assert_eq!(SearchOptions::parse(Some("d1"), None).region, None);
    }
}
