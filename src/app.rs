use axum::{middleware, routing::get, Json, Router};
use serde_json::json;

use crate::{
    app_state::AppState,
    middleware::tracing::observability_middleware,
    modules::admin::routes::admin_routes,
    websocket::websocket_routes,
};

pub fn create_router(state: AppState) -> Router {
    let ws_tx_cloned = state.ws_tx.clone();

    let ws_app = websocket_routes().with_state(ws_tx_cloned);

    // HTMX Router
    let htmx_app = admin_routes();

    let static_dir = state.env.app.static_dir.to_string();

    Router::new()
        .route("/", get(hello))
        .route("/health", get(health_check))
        .merge(ws_app)
        .nest("/admin", htmx_app)
        .nest_service(
            "/static",
            tower_http::services::ServeDir::new(static_dir),
        )
        .layer(middleware::from_fn(observability_middleware))
        .with_state(state)
}

async fn hello() -> &'static str {
    "OHS Backend says hello!\n"
}

async fn health_check(
    axum::extract::State(state): axum::extract::State<AppState>,
) -> Json<serde_json::Value> {
    let db_result = sqlx::query("SELECT 1").execute(&state.db).await;

    let db_status = match db_result {
        Ok(_) => "healthy",
        Err(e) => {
            tracing::info!("Database health check failed: {}", e);
            "unhealthy"
        }
    };

    // Get telemetry health status
    let telemetry_health = crate::telemetry::telemetry_health_check();

    Json(json!({
        "status": "ok",
        "timestamp": chrono::Utc::now().to_rfc3339(),
        "version": env!("CARGO_PKG_VERSION"),
        "services": {
            "database": db_status,
            "telemetry": telemetry_health
        }
    }))
}
