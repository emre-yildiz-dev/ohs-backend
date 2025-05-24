use axum::{
    routing::get,
    Router,
};

use crate::app_state::AppState;
use super::handlers::{
    get_current_language,
    get_supported_languages,
    get_translations,
};
use super::example_handler::{
    example_localized_handler,
    example_multi_language_handler,
};

/// Create i18n routes
pub fn create_i18n_routes() -> Router<AppState> {
    Router::new()
        .route("/languages", get(get_supported_languages))
        .route("/translations", get(get_translations))
        .route("/current-language", get(get_current_language))
        .route("/example", get(example_localized_handler))
        .route("/example-multi", get(example_multi_language_handler))
} 