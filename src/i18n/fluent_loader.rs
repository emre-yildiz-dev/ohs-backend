use anyhow::{Context, Result};
use fluent_bundle::{concurrent::FluentBundle, FluentResource};
use std::collections::HashMap;
use std::fs;
use std::path::Path;

use crate::i18n::language::SupportedLanguage;

pub type Bundle = FluentBundle<FluentResource>;

/// Loads and manages Fluent translation resources
pub struct FluentLoader {
    bundles: HashMap<SupportedLanguage, Bundle>,
}

impl FluentLoader {
    pub fn new() -> Self {
        Self {
            bundles: HashMap::new(),
        }
    }

    /// Load all FTL files for a specific locale
    pub async fn load_locale(&mut self, language: SupportedLanguage) -> Result<()> {
        let lang_id = language.lang_id();
        let mut bundle = FluentBundle::new_concurrent(vec![lang_id]);

        let locale_dir = format!("locales/{}", language.code());
        
        if !Path::new(&locale_dir).exists() {
            fs::create_dir_all(&locale_dir)
                .with_context(|| format!("Failed to create locale directory: {}", locale_dir))?;
        }

        // Load all .ftl files in the locale directory
        let paths = fs::read_dir(&locale_dir)
            .with_context(|| format!("Failed to read locale directory: {}", locale_dir))?;

        let mut loaded_files = 0;
        for path in paths {
            let path = path?.path();
            if path.extension().and_then(|s| s.to_str()) == Some("ftl") {
                let content = fs::read_to_string(&path)
                    .with_context(|| format!("Failed to read file: {:?}", path))?;

                let resource = FluentResource::try_new(content)
                    .map_err(|(_, errors)| {
                        anyhow::anyhow!("Failed to parse FTL file {:?}: {:?}", path, errors)
                    })?;

                bundle.add_resource(resource)
                    .map_err(|errors| {
                        anyhow::anyhow!("Failed to add resource to bundle: {:?}", errors)
                    })?;

                loaded_files += 1;
            }
        }

        // If no files were loaded, create a default file
        if loaded_files == 0 {
            self.create_default_ftl_file(&language).await?;
            // Reload after creating default file
            return Box::pin(self.load_locale(language)).await;
        }

        tracing::info!("Loaded {} FTL files for locale {}", loaded_files, language.code());
        
        self.bundles.insert(language, bundle);
        Ok(())
    }

    /// Get a bundle for a specific language
    pub fn get_bundle(&self, language: &SupportedLanguage) -> Option<&Bundle> {
        self.bundles.get(language)
    }

    /// Create a default FTL file for a language if it doesn't exist
    async fn create_default_ftl_file(&self, language: &SupportedLanguage) -> Result<()> {
        let locale_dir = format!("locales/{}", language.code());
        let file_path = format!("{}/common.ftl", locale_dir);

        let default_content = match language {
            SupportedLanguage::Turkish => include_str!("../../locales/tr/common.ftl.template"),
            SupportedLanguage::English => include_str!("../../locales/en/common.ftl.template"),
        };

        fs::write(&file_path, default_content)
            .with_context(|| format!("Failed to create default FTL file: {}", file_path))?;

        tracing::info!("Created default FTL file: {}", file_path);
        Ok(())
    }
}

impl Default for FluentLoader {
    fn default() -> Self {
        Self::new()
    }
}