use anyhow::{Context, Result};
use serde::Deserialize;
use std::env;
use std::net::{IpAddr, SocketAddr};
use std::str::FromStr;

#[derive(Debug, Clone, Deserialize)]
#[allow(unused)]
pub struct Config {
    pub server: ServerConfig,
    pub database: DatabaseConfig,
    pub redis: RedisConfig,
    pub s3: Option<S3Config>,
    pub turn: Option<TurnConfig>,
    pub app: AppConfig,
}

#[derive(Debug, Clone, Deserialize)]    
#[allow(unused)]
pub struct ServerConfig {
    pub host: IpAddr,
    pub port: u16,
    pub workers: Option<usize>,
}

#[derive(Debug, Clone, Deserialize)]
#[allow(unused)]
pub struct DatabaseConfig {
    pub url: String,
    pub max_connections: Option<u32>,
    pub min_connections: Option<u32>,
}

#[derive(Debug, Clone, Deserialize)]
#[allow(unused)]
pub struct RedisConfig {
    pub url: String,
}

#[derive(Debug, Clone, Deserialize)]
#[allow(unused)]
pub struct S3Config {
    pub endpoint: String,
    pub access_key_id: String,
    pub secret_access_key: String,
    pub bucket_name: String,
    pub region: Option<String>,
}

#[derive(Debug, Clone, Deserialize)]
#[allow(unused)]
pub struct TurnConfig {
    pub url_udp: Option<String>,
    pub url_tcp: Option<String>,
    pub username: String,
    pub password: String,
}

#[derive(Debug, Clone, Deserialize)]
#[allow(unused)]
pub struct AppConfig {
    pub name: String,
    pub environment: Environment,
    pub static_dir: String,
    pub templates_dir: String,
}

#[derive(Debug, Clone, Copy, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum Environment {
    Development,
    Staging,
    Production,
}

impl Config {
    pub fn from_env() -> Result<Self> {
        // Server configuration
        let host = env::var("SERVER_HOST")
            .unwrap_or_else(|_| "0.0.0.0".to_string())
            .parse::<IpAddr>()
            .context("Failed to parse SERVER_HOST")?;
            
        let port = env::var("SERVER_PORT")
            .unwrap_or_else(|_| "8000".to_string())
            .parse::<u16>()
            .context("Failed to parse SERVER_PORT")?;
            
        let workers = match env::var("SERVER_WORKERS") {
            Ok(val) => Some(val.parse().context("Failed to parse SERVER_WORKERS")?),
            Err(_) => None,
        };

        // Database configuration
        let db_url = env::var("DATABASE_URL").context("DATABASE_URL must be set")?;
        let db_max_connections = match env::var("DATABASE_MAX_CONNECTIONS") {
            Ok(val) => Some(val.parse().context("Failed to parse DATABASE_MAX_CONNECTIONS")?),
            Err(_) => Some(10), // Default value
        };
        let db_min_connections = match env::var("DATABASE_MIN_CONNECTIONS") {
            Ok(val) => Some(val.parse().context("Failed to parse DATABASE_MIN_CONNECTIONS")?),
            Err(_) => Some(1), // Default value
        };

        // Redis configuration
        let redis_url = env::var("REDIS_URL").context("REDIS_URL must be set")?;

        // S3 configuration (optional)
        let s3_config = if let Ok(endpoint) = env::var("S3_ENDPOINT") {
            let access_key_id = env::var("S3_ACCESS_KEY_ID")
                .context("S3_ACCESS_KEY_ID must be set when S3_ENDPOINT is provided")?;
            let secret_access_key = env::var("S3_SECRET_ACCESS_KEY")
                .context("S3_SECRET_ACCESS_KEY must be set when S3_ENDPOINT is provided")?;
            let bucket_name = env::var("S3_BUCKET_NAME")
                .context("S3_BUCKET_NAME must be set when S3_ENDPOINT is provided")?;
            let region = env::var("S3_REGION").ok();

            Some(S3Config {
                endpoint,
                access_key_id,
                secret_access_key,
                bucket_name,
                region,
            })
        } else {
            None
        };

        // TURN server configuration (optional)
        let turn_config = if let (Ok(username), Ok(password)) = 
            (env::var("TURN_USERNAME"), env::var("TURN_PASSWORD")) {
            let url_udp = env::var("TURN_URL_UDP").ok();
            let url_tcp = env::var("TURN_URL_TCP").ok();

            Some(TurnConfig {
                url_udp,
                url_tcp,
                username,
                password,
            })
        } else {
            None
        };

        // App configuration
        let environment_str = env::var("APP_ENVIRONMENT")
            .unwrap_or_else(|_| "development".to_string());
        let environment = match environment_str.to_lowercase().as_str() {
            "production" => Environment::Production,
            "staging" => Environment::Staging,
            _ => Environment::Development,
        };

        let app_name = env::var("APP_NAME").unwrap_or_else(|_| "OHS Backend".to_string());
        let static_dir = env::var("STATIC_DIR").unwrap_or_else(|_| "static".to_string());
        let templates_dir = env::var("TEMPLATES_DIR").unwrap_or_else(|_| "templates".to_string());

        Ok(Config {
            server: ServerConfig {
                host,
                port,
                workers,
            },
            database: DatabaseConfig {
                url: db_url,
                max_connections: db_max_connections,
                min_connections: db_min_connections,
            },
            redis: RedisConfig {
                url: redis_url,
            },
            s3: s3_config,
            turn: turn_config,
            app: AppConfig {
                name: app_name,
                environment,
                static_dir,
                templates_dir,
            },
        })
    }

    pub fn server_addr(&self) -> SocketAddr {
        SocketAddr::new(self.server.host, self.server.port)
    }

    #[allow(unused)]
    pub fn is_production(&self) -> bool {
        self.app.environment == Environment::Production
    }

    #[allow(unused)]
    pub fn is_development(&self) -> bool {
        self.app.environment == Environment::Development
    }
}

impl Default for Environment {
    fn default() -> Self {
        Environment::Development
    }
}

impl FromStr for Environment {
    type Err = String;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        match s.to_lowercase().as_str() {
            "production" => Ok(Environment::Production),
            "staging" => Ok(Environment::Staging),
            "development" => Ok(Environment::Development),
            _ => Err(format!("Unknown environment: {}", s)),
        }
    }
}

// Use once_cell for a global config instance that's initialized once
use once_cell::sync::OnceCell;

static CONFIG: OnceCell<Config> = OnceCell::new();

pub fn init() -> Result<&'static Config> {
    CONFIG.get_or_try_init(Config::from_env)
}

pub fn get() -> &'static Config {
    CONFIG.get().expect("Config is not initialized")
}