mod repositories;
mod models;
mod error;

use sqlx::postgres::{PgPoolOptions, PgPool};
use anyhow::Result;
use crate::config;

pub use error::DatabaseError;
pub use models::*;

/// Initialize the database connection pool
pub async fn init_pool() -> Result<PgPool> {
    let config = config::get();
    let pool = PgPoolOptions::new()
        .max_connections(config.database.max_connections.unwrap_or(10))
        .min_connections(config.database.min_connections.unwrap_or(1))
        .connect(&config.database.url)
        .await?;
    
    // Run migrations
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await?;
    
    Ok(pool)
}
