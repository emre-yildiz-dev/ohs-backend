use anyhow::Context;
use axum::{Router, routing::get};
use dotenv::dotenv;
use modules::admin::handlers::{admin_dashboard, admin_login};
use tracing::info;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

mod modules;
mod config;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| format!("{}=debug", env!("CARGO_CRATE_NAME")).into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    dotenv().ok();

    let config = config::init()?;

    // HTMX Router
    let htmx_app = Router::new()
        .route("/", get(admin_dashboard))
        .route("/login", get(admin_login));

    let static_dir = format!("{}", config.app.static_dir);

    let app = Router::new()
        .route("/", get(hello))
        .nest("/admin", htmx_app)
        .nest_service("/static", tower_http::services::ServeDir::new(static_dir));

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
