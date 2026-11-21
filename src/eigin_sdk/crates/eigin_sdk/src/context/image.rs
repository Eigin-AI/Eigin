const DEFAULT_IMAGE_DIMENSION: i64 = 1024;
const MINIMUM_IMAGE_DIMENSION: i64 = 1;
const GPT_4O_MINI_TILE_SIZE: i64 = 512;
const GPT_4O_MINI_MINIMUM_TILES: i64 = 4;
const GPT_4O_MINI_BASE_TOKENS: i64 = 2833;
const GPT_4O_MINI_TOKENS_PER_TILE: i64 = 5667;
const IMAGE_PATCH_SIZE: i64 = 32;
const IMAGE_BASE_TOKENS: i64 = 256;
const IMAGE_TOKENS_PER_PATCH: i64 = 3;
const UNKNOWN_MODEL_MINIMUM_TOKENS: i64 = 32768;

/// Conservative context allowance selected by resolved catalog identity.
pub(crate) fn catalog_image_budget(
    width: Option<i64>,
    height: Option<i64>,
    pattern: Option<&str>,
) -> i64 {
    let width = width
        .unwrap_or(DEFAULT_IMAGE_DIMENSION)
        .max(MINIMUM_IMAGE_DIMENSION);
    let height = height
        .unwrap_or(DEFAULT_IMAGE_DIMENSION)
        .max(MINIMUM_IMAGE_DIMENSION);
    if pattern == Some("gpt-4o-mini") {
        let tiles = ((width - 1) / GPT_4O_MINI_TILE_SIZE + 1)
            .saturating_mul((height - 1) / GPT_4O_MINI_TILE_SIZE + 1);
        return GPT_4O_MINI_BASE_TOKENS.saturating_add(
            GPT_4O_MINI_TOKENS_PER_TILE.saturating_mul(tiles.max(GPT_4O_MINI_MINIMUM_TILES)),
        );
    }
    let patches =
        ((width - 1) / IMAGE_PATCH_SIZE + 1).saturating_mul((height - 1) / IMAGE_PATCH_SIZE + 1);
    let budget = IMAGE_BASE_TOKENS.saturating_add(IMAGE_TOKENS_PER_PATCH.saturating_mul(patches));
    if pattern.is_none() {
        budget.max(UNKNOWN_MODEL_MINIMUM_TOKENS)
    } else {
        budget
    }
}
