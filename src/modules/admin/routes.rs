use axum::{Router, routing::get};
use crate::app_state::AppState;
use super::handlers::{admin_dashboard, admin_login};

pub fn admin_routes() -> Router<AppState> {
    Router::new()
        .route("/", get(admin_dashboard))
        .route("/login", get(admin_login))
} 