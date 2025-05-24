use anyhow::Context;
use app_state::AppState;
use dotenvy::dotenv;
use tracing::info;
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
mod telemetry;
mod middleware;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    dotenv().ok();

    // Initialize OpenTelemetry
    let telemetry_handles = telemetry::init_telemetry(None).await
        .context("Failed to initialize telemetry")?;

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

    // Setup graceful shutdown
    let server = axum::serve(listener, app);
    
    tokio::select! {
        result = server => {
            if let Err(err) = result {
                tracing::error!("Server error: {}", err);
            }
        }
        _ = tokio::signal::ctrl_c() => {
            info!("Received shutdown signal, shutting down gracefully...");
        }
    }

    // Shutdown telemetry providers
    telemetry_handles.shutdown().await
        .context("Failed to shutdown telemetry")?;

    info!("Application shutdown completed");
    Ok(())
}
