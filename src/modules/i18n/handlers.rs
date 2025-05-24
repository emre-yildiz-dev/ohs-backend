use axum::{
    extract::{Query, State},
    http::StatusCode,
    response::Json,
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use crate::app_state::AppState;
use crate::i18n::{extract_translations_for_client, SupportedLanguage};
use crate::middleware::LanguageExtractor;

#[derive(Debug, Deserialize)]
pub struct TranslationQuery {
    pub keys: Option<String>, // Comma-separated list of keys
    pub language: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct LanguageInfo {
    pub code: String,
    pub name: String,
    pub is_default: bool,
}

#[derive(Debug, Serialize)]
pub struct SupportedLanguagesResponse {
    pub languages: Vec<LanguageInfo>,
    pub default_language: String,
}

#[derive(Debug, Serialize)]
pub struct TranslationsResponse {
    pub translations: HashMap<String, String>,
    pub language: String,
    pub requested_keys: Vec<String>,
}

/// Get all supported languages
pub async fn get_supported_languages(
    State(_state): State<AppState>,
) -> Result<Json<SupportedLanguagesResponse>, StatusCode> {
    let languages = SupportedLanguage::all()
        .iter()
        .map(|lang| LanguageInfo {
            code: lang.code().to_string(),
            name: lang.name().to_string(),
            is_default: *lang == SupportedLanguage::default(),
        })
        .collect();

    let response = SupportedLanguagesResponse {
        languages,
        default_language: SupportedLanguage::default().code().to_string(),
    };

    Ok(Json(response))
}

/// Get translations for specific keys
pub async fn get_translations(
    State(state): State<AppState>,
    Query(query): Query<TranslationQuery>,
) -> Result<Json<TranslationsResponse>, StatusCode> {
    // Parse language from query or use default
    let language = if let Some(lang_str) = query.language {
        lang_str.parse::<SupportedLanguage>()
            .unwrap_or(SupportedLanguage::default())
    } else {
        SupportedLanguage::default()
    };

    // Parse keys from query
    let keys: Vec<String> = if let Some(keys_str) = query.keys {
        keys_str.split(',').map(|s| s.trim().to_string()).collect()
    } else {
        // Default keys for common UI elements
        vec![
            "app-name".to_string(), "welcome".to_string(), "login".to_string(), 
            "logout".to_string(), "email".to_string(), "password".to_string(),
            "save".to_string(), "cancel".to_string(), "create".to_string(), 
            "edit".to_string(), "delete".to_string(), "loading".to_string(),
            "error-generic".to_string(), "success-saved".to_string()
        ]
    };

    let key_refs: Vec<&str> = keys.iter().map(|s| s.as_str()).collect();

    let translations = extract_translations_for_client(
        &state.localizer,
        language,
        &key_refs,
    );

    let response = TranslationsResponse {
        translations,
        language: language.code().to_string(),
        requested_keys: keys.iter().map(|s| s.to_string()).collect(),
    };

    Ok(Json(response))
}

/// Get current language information
pub async fn get_current_language(
    req: axum::extract::Request,
) -> Result<Json<LanguageInfo>, StatusCode> {
    let language = req.get_language();
    
    let info = LanguageInfo {
        code: language.code().to_string(),
        name: language.name().to_string(),
        is_default: language == SupportedLanguage::default(),
    };

    Ok(Json(info))
} 