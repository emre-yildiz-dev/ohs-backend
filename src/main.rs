use axum::{routing::get, Router};
use tracing::info;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};
use anyhow::Context;
use dotenv::dotenv;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| format!("{}=debug", env!("CARGO_CRATE_NAME")).into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

        let app = Router::new()
            .route("/", get(hello)
    );
    dotenv().ok();

    let port = 8000_u16;
    let addr = std::net::SocketAddr::from(([0, 0, 0, 0], port));

    let app_name = std::env::var("CARGO_CRATE_NAME").unwrap_or_default().to_string();
    info!("{} Listening on {}", app_name, addr);

    let listener = tokio::net::TcpListener::bind(addr).await.context("Failed to bind to address")?;
    axum::serve(listener, app).await.context("Failed to serve application")?;

    Ok(())
}

async fn hello() -> &'static str {
    "OHS Backend says hello!\n"
}
