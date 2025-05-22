use axum::{Router, routing::get};
use std::sync::{Arc, Mutex};
use tokio::sync::broadcast::Sender;
use super::ws_handler;

pub fn websocket_routes() -> Router<Arc<Mutex<Sender<String>>>> {
    Router::new().route("/ws", get(ws_handler))
} 