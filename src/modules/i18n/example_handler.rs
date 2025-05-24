use axum::{response::Json, http::StatusCode};
use serde::Serialize;

use crate::i18n::{I18n, SupportedLanguage};
use crate::i18n_args;

#[derive(Serialize)]
pub struct ExampleResponse {
    pub message: String,
    pub welcome_message: String,
    pub language: String,
    pub app_name: String,
}

/// Example handler showing how to use i18n in practice
pub async fn example_localized_handler(
    i18n: I18n,
) -> Result<Json<ExampleResponse>, StatusCode> {
    // Simple message without arguments
    let message = i18n.get("app-description");
    
    // Message with arguments using the helper macro
    let welcome_args = i18n_args! {
        "name" => "Emre"
    };
    let welcome_message = i18n.get_with_args("welcome", &welcome_args);
    
    // Get app name
    let app_name = i18n.get("app-name");
    
    let response = ExampleResponse {
        message,
        welcome_message,
        language: i18n.language().name().to_string(),
        app_name,
    };

    Ok(Json(response))
}

/// Example showing how to handle different languages
pub async fn example_multi_language_handler(
    i18n: I18n,
) -> Result<Json<serde_json::Value>, StatusCode> {
    let mut responses = serde_json::Map::new();
    
    // Get the same message in all supported languages
    for lang in SupportedLanguage::all() {
        let localizer = &i18n.localizer;
        let message = localizer.get_string_for_language(lang, "app-name");
        responses.insert(lang.code().to_string(), serde_json::Value::String(message));
    }
    
    Ok(Json(serde_json::Value::Object(responses)))
} 