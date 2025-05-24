use serde::{Deserialize, Serialize};
use std::fmt::{self, Display};
use std::str::FromStr;
use unic_langid::LanguageIdentifier;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum SupportedLanguage {
    #[serde(rename = "tr")]
    Turkish,
    #[serde(rename = "en")]
    English,
}

impl SupportedLanguage {
    /// Get all supported languages
    pub fn all() -> &'static [SupportedLanguage] {
        &[SupportedLanguage::Turkish, SupportedLanguage::English]
    }

    /// Get the default language (Turkish)
    pub fn default() -> Self {
        SupportedLanguage::Turkish
    }

    /// Get the language code as a string
    pub fn code(&self) -> &'static str {
        match self {
            SupportedLanguage::Turkish => "tr",
            SupportedLanguage::English => "en",
        }
    }

    /// Get the language identifier for Fluent
    pub fn lang_id(&self) -> LanguageIdentifier {
        match self {
            SupportedLanguage::Turkish => "tr".parse().unwrap(),
            SupportedLanguage::English => "en-US".parse().unwrap(),
        }
    }

    /// Get the human-readable name
    pub fn name(&self) -> &'static str {
        match self {
            SupportedLanguage::Turkish => "Türkçe",
            SupportedLanguage::English => "English",
        }
    }

    /// Parse from Accept-Language header
    pub fn from_accept_language(accept_language: &str) -> Self {
        for lang_part in accept_language.split(',') {
            let lang = lang_part.trim().split(';').next().unwrap_or("");
            let lang = lang.to_lowercase();
            
            if lang.starts_with("tr") {
                return SupportedLanguage::Turkish;
            } else if lang.starts_with("en") {
                return SupportedLanguage::English;
            }
        }
        
        // Default to Turkish if no supported language is found
        Self::default()
    }
}

impl Display for SupportedLanguage {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.code())
    }
}

impl FromStr for SupportedLanguage {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "tr" | "turkish" | "türkçe" => Ok(SupportedLanguage::Turkish),
            "en" | "english" | "en-us" => Ok(SupportedLanguage::English),
            _ => Err(format!("Unsupported language: {}", s)),
        }
    }
}

/// Trait for objects that can be localized
pub trait Language {
    /// Get the preferred language from request headers or user settings
    #[allow(dead_code)]
    fn get_language(&self) -> SupportedLanguage;
} 