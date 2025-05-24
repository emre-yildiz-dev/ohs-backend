# Testing the i18n System

## Quick Test Commands

Once the server is running, you can test the i18n endpoints:

```bash
# Start the server
cargo run

# Test supported languages
curl http://localhost:3000/api/i18n/languages

# Test translations (default language - Turkish)
curl http://localhost:3000/api/i18n/translations

# Test translations for specific language
curl http://localhost:3000/api/i18n/translations?language=en

# Test specific keys
curl "http://localhost:3000/api/i18n/translations?keys=app-name,welcome,login"

# Test with language header
curl -H "X-Language: en" http://localhost:3000/api/i18n/current-language

# Test Accept-Language header
curl -H "Accept-Language: en-US,en;q=0.9" http://localhost:3000/api/i18n/current-language

# Test example handler with Turkish (default)
curl http://localhost:3000/api/i18n/example

# Test example handler with English
curl -H "X-Language: en" http://localhost:3000/api/i18n/example

# Test multi-language example
curl http://localhost:3000/api/i18n/example-multi
```

## Expected Responses

The system should:
1. Automatically create translation files if they don't exist
2. Detect language from headers (X-Language takes priority over Accept-Language)
3. Fall back to Turkish as the default language
4. Return properly formatted JSON responses with translations
5. Handle missing translation keys gracefully 