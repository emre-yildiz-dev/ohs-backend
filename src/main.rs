use anyhow::Context;
use app_state::AppState;
use dotenvy::dotenv;
use tracing::info;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
use tokio::sync::broadcast;
use std::sync::{Arc, Mutex};
use crate::app::create_router;

mod modules;
mod config;
mod websocket;
mod app_state;
mod db;
mod error;
mod app;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    dotenv().ok();

    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| format!("{}=debug", env!("CARGO_CRATE_NAME")).into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    let config = config::init()?;
    
    let db_pool = db::init_pool().await?;
    info!("Database connection established");

    let (tx, _rx) = broadcast::channel::<String>(100);
    let ws_broadcaster = Arc::new(Mutex::new(tx));

    let state = AppState::new(db_pool, config.clone(), ws_broadcaster);

    let app = create_router(state);

    let addr = config.server_addr();

    info!("{} Listening on http://{}", config.app.name, addr);

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .context("Failed to bind to address")?;

    axum::serve(listener, app)
        .await
        .context("Failed to serve application")?;

    Ok(())
}
