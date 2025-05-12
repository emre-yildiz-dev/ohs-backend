use anyhow::Context;
use app_state::AppState;
use axum::{Router, routing::get, Json};
use dotenvy::dotenv;
use modules::admin::handlers::{admin_dashboard, admin_login};
use serde_json::json;
use tracing::info;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
use tokio::sync::broadcast;
use std::sync::{Arc, Mutex};
use websocket::ws_handler;

mod modules;
mod config;
mod websocket;
mod app_state;
mod db;
mod error;

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
    
    // Initialize database connection pool
    let db_pool = db::init_pool().await?;
    info!("Database connection established");

    let (tx, _rx) = broadcast::channel(100);
    let ws_state = Arc::new(Mutex::new(tx));

    // Create app state with DB pool
    let state = AppState::new(db_pool, ws_state.clone());

    let ws_app = Router::new()
        .route("/ws", get(ws_handler))
        .with_state(ws_state);

    // HTMX Router
    let htmx_app = Router::new()
        .route("/", get(admin_dashboard))
        .route("/login", get(admin_login));

    let static_dir = format!("{}", config.app.static_dir);

    let app = Router::new()
        .route("/", get(hello))
        .route("/health", get(health_check))
        .merge(ws_app)
        .nest("/admin", htmx_app)
        .nest_service("/static", tower_http::services::ServeDir::new(static_dir))
        .with_state(state);

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

async fn hello() -> &'static str {
    "OHS Backend says hello!\n"
}

async fn health_check(
    axum::extract::State(state): axum::extract::State<AppState>
) -> Json<serde_json::Value> {
    let db_result = sqlx::query("SELECT 1").execute(&state.db).await;
    
    let db_status = match db_result {
        Ok(_) => "healthy",
        Err(e) => {
            info!("Database health check failed: {}", e);
            "unhealthy"
        }
    };
    
    Json(json!({
        "status": "ok",
        "timestamp": chrono::Utc::now().to_rfc3339(),
        "version": env!("CARGO_PKG_VERSION"),
        "services": {
            "database": db_status
        }
    }))
}
