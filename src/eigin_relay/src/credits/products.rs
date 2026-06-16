//! GET /credits/products — list the credit products available for purchase.
//!
//! The client fetches this catalog before any wallet exists, then resolves the
//! product IDs against the store (StoreKit/Play) for live prices. Credits are the
//! relay's authority; price and display name belong to the store, so they are not
//! carried here.

use std::sync::Arc;

use axum::Json;
use axum::extract::State;
use axum::response::IntoResponse;
use serde::Serialize;

use crate::AppState;

#[derive(Serialize)]
struct ProductInfo {
    /// Store product ID, e.g. `eigin.credits.v1.apple.500`.
    id: String,
    /// Whole credits granted on redemption (floor division of millicredits).
    credits: i64,
}

#[derive(Serialize)]
struct ProductsResponse {
    products: Vec<ProductInfo>,
}

pub async fn handle(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    let mut products: Vec<ProductInfo> = state
        .product_credits
        .iter()
        .map(|(id, millicredits)| ProductInfo {
            id: id.clone(),
            credits: millicredits / 1000,
        })
        .collect();
    // Stable, deterministic ordering for clients and tests.
    products.sort_by(|a, b| a.id.cmp(&b.id));
    Json(ProductsResponse { products })
}
