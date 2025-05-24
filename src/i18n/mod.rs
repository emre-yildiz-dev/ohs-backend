pub mod fluent_loader;
pub mod language;
pub mod localizer;
pub mod helpers;

pub use fluent_loader::FluentLoader;
pub use language::{Language, SupportedLanguage};
pub use localizer::{Localizer, LocalizedString};
pub use helpers::I18n;

use anyhow::Result;
use std::collections::HashMap;

/// Initialize the i18n system with default locales
pub async fn init_i18n() -> Result<Localizer> {
    let mut loader = FluentLoader::new();
    
    // Load Turkish (default) and English
    loader.load_locale(SupportedLanguage::Turkish).await?;
    loader.load_locale(SupportedLanguage::English).await?;
    
    Ok(Localizer::new(loader))
}

/// Extract a dictionary of key-value pairs for client-side usage
pub fn extract_translations_for_client(
    localizer: &Localizer,
    language: SupportedLanguage,
    keys: &[&str],
) -> HashMap<String, String> {
    let mut translations = HashMap::new();
    
    for key in keys {
        if let Ok(translation) = localizer.get_message_with_language(&language, key, None) {
            translations.insert(key.to_string(), translation.into_string());
        }
    }
    
    translations
} 