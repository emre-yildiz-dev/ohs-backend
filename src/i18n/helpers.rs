use axum::{
    extract::FromRequestParts,
    http::{StatusCode, request::Parts},
};
use fluent_bundle::FluentValue;
use std::collections::HashMap;

use crate::app_state::AppState;
use crate::i18n::{LocalizedString, Localizer, SupportedLanguage};

/// Extractor for getting localized messages in handlers
pub struct I18n {
    pub localizer: std::sync::Arc<Localizer>,
    pub language: SupportedLanguage,
}

impl I18n {
    /// Get a localized message
    pub fn get(&self, key: &str) -> String {
        self.localizer.get_string_for_language(&self.language, key)
    }

    /// Get a localized message with arguments
    pub fn get_with_args(&self, key: &str, args: &HashMap<String, FluentValue>) -> String {
        self.localizer
            .get_message_with_language(&self.language, key, Some(args))
            .unwrap_or_else(|_| LocalizedString::new(key.to_string(), self.language))
            .into_string()
    }

    /// Get the current language
    pub fn language(&self) -> SupportedLanguage {
        self.language
    }

    /// Check if a message exists
    #[allow(dead_code)]
    pub fn has_message(&self, key: &str) -> bool {
        self.localizer.has_message(&self.language, key)
    }
}

impl FromRequestParts<AppState> for I18n {
    type Rejection = StatusCode;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        // Extract language directly from extensions
        let language = parts
            .extensions
            .get::<SupportedLanguage>()
            .copied()
            .unwrap_or(SupportedLanguage::default());

        Ok(I18n {
            localizer: state.localizer.clone(),
            language,
        })
    }
}

/// Helper macro for creating FluentValue arguments easily
#[macro_export]
macro_rules! i18n_args {
    ($($key:expr => $value:expr),* $(,)?) => {{
        let mut args = std::collections::HashMap::new();
        $(
            args.insert($key.to_string(), fluent_bundle::FluentValue::from($value));
        )*
        args
    }};
}
