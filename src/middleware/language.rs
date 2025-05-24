use axum::{
    extract::Request,
    http::HeaderMap,
    middleware::Next,
    response::Response,
};
use crate::i18n::{SupportedLanguage, Language};

/// Language detection middleware that extracts language preference from headers
pub async fn language_middleware(
    mut request: Request,
    next: Next,
) -> Response {
    let language = detect_language_from_headers(request.headers());
    
    // Add the detected language to request extensions
    request.extensions_mut().insert(language);
    
    next.run(request).await
}

/// Detect language from various HTTP headers
fn detect_language_from_headers(headers: &HeaderMap) -> SupportedLanguage {
    // Priority order for language detection:
    // 1. X-Language header (explicit language setting)
    // 2. Accept-Language header (browser preference)
    
    // Check for explicit language header
    if let Some(lang_header) = headers.get("X-Language") {
        if let Ok(lang_str) = lang_header.to_str() {
            if let Ok(language) = lang_str.parse::<SupportedLanguage>() {
                return language;
            }
        }
    }
    
    // Check Accept-Language header
    if let Some(accept_language) = headers.get("Accept-Language") {
        if let Ok(accept_language_str) = accept_language.to_str() {
            return SupportedLanguage::from_accept_language(accept_language_str);
        }
    }
    
    // Default to Turkish
    SupportedLanguage::default()
}

/// Extension trait for extracting language from request
pub trait LanguageExtractor {
    fn get_language(&self) -> SupportedLanguage;
}

impl LanguageExtractor for Request {
    fn get_language(&self) -> SupportedLanguage {
        self.extensions()
            .get::<SupportedLanguage>()
            .copied()
            .unwrap_or(SupportedLanguage::default())
    }
}

impl Language for Request {
    fn get_language(&self) -> SupportedLanguage {
        LanguageExtractor::get_language(self)
    }
} 