use anyhow::{anyhow, Result};
use fluent_bundle::{FluentArgs, FluentValue};
use serde::Serialize;
use std::collections::HashMap;
use std::fmt;

use crate::i18n::fluent_loader::FluentLoader;
use crate::i18n::language::SupportedLanguage;

/// A localized string that can be converted to different formats
#[derive(Debug, Clone, Serialize)]
pub struct LocalizedString {
    value: String,
    language: SupportedLanguage,
}

impl LocalizedString {
    pub fn new(value: String, language: SupportedLanguage) -> Self {
        Self { value, language }
    }

    pub fn into_string(self) -> String {
        self.value
    }

    pub fn as_str(&self) -> &str {
        &self.value
    }

    pub fn language(&self) -> SupportedLanguage {
        self.language
    }
}

impl fmt::Display for LocalizedString {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.value)
    }
}

impl From<LocalizedString> for String {
    fn from(ls: LocalizedString) -> Self {
        ls.value
    }
}

/// Main localization interface
pub struct Localizer {
    loader: FluentLoader,
    default_language: SupportedLanguage,
}

#[allow(dead_code)]
impl Localizer {
    pub fn new(loader: FluentLoader) -> Self {
        Self {
            loader,
            default_language: SupportedLanguage::default(),
        }
    }

    /// Get a localized message using automatic language detection
    pub fn get_message(
        &self,
        key: &str,
        args: Option<&HashMap<String, FluentValue>>,
    ) -> Result<LocalizedString> {
        self.get_message_with_language(&self.default_language, key, args)
    }

    /// Get a localized message for a specific language
    pub fn get_message_with_language(
        &self,
        language: &SupportedLanguage,
        key: &str,
        args: Option<&HashMap<String, FluentValue>>,
    ) -> Result<LocalizedString> {
        let bundle = self
            .loader
            .get_bundle(language)
            .or_else(|| self.loader.get_bundle(&self.default_language))
            .ok_or_else(|| anyhow!("No bundle available for language: {}", language))?;

        let message = bundle
            .get_message(key)
            .ok_or_else(|| anyhow!("Message not found: {}", key))?;

        let pattern = message
            .value()
            .ok_or_else(|| anyhow!("Message has no value: {}", key))?;

        let mut errors = Vec::new();
        let formatted = if let Some(args) = args {
            let mut fluent_args = FluentArgs::new();
            for (k, v) in args {
                fluent_args.set(k, v.clone());
            }
            bundle.format_pattern(pattern, Some(&fluent_args), &mut errors)
        } else {
            bundle.format_pattern(pattern, None, &mut errors)
        };

        if !errors.is_empty() {
            tracing::warn!("Fluent formatting errors for key '{}': {:?}", key, errors);
        }

        Ok(LocalizedString::new(formatted.into_owned(), *language))
    }

    /// Get a simple string message (convenience method)
    pub fn get_string(&self, key: &str) -> String {
        self.get_message(key, None)
            .unwrap_or_else(|_| LocalizedString::new(key.to_string(), self.default_language))
            .into_string()
    }

    /// Get a string message with arguments
    pub fn get_string_with_args(
        &self,
        key: &str,
        args: &HashMap<String, FluentValue>,
    ) -> String {
        self.get_message(key, Some(args))
            .unwrap_or_else(|_| LocalizedString::new(key.to_string(), self.default_language))
            .into_string()
    }

    /// Get a message for a specific language (convenience method)
    pub fn get_string_for_language(
        &self,
        language: &SupportedLanguage,
        key: &str,
    ) -> String {
        self.get_message_with_language(language, key, None)
            .unwrap_or_else(|_| LocalizedString::new(key.to_string(), *language))
            .into_string()
    }

    /// Check if a message exists for a language
    pub fn has_message(&self, language: &SupportedLanguage, key: &str) -> bool {
        self.loader
            .get_bundle(language)
            .map(|bundle| bundle.has_message(key))
            .unwrap_or(false)
    }

    /// Get all supported languages
    pub fn supported_languages(&self) -> &'static [SupportedLanguage] {
        SupportedLanguage::all()
    }

    /// Set the default language
    pub fn set_default_language(&mut self, language: SupportedLanguage) {
        self.default_language = language;
    }

    /// Get the current default language
    pub fn default_language(&self) -> SupportedLanguage {
        self.default_language
    }
}

/// Helper macro for creating FluentValue arguments
#[macro_export]
macro_rules! fluent_args {
    ($($key:expr => $value:expr),* $(,)?) => {{
        let mut args = std::collections::HashMap::new();
        $(
            args.insert($key.to_string(), fluent_bundle::FluentValue::from($value));
        )*
        args
    }};
}

/// Helper function to create FluentValue from common types
#[allow(dead_code)]
pub fn fluent_value_from<T>(value: T) -> FluentValue<'static>
where
    T: Into<FluentValue<'static>>,
{
    value.into()
} 